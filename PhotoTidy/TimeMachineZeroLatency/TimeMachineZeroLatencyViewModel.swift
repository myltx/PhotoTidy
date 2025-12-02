import Foundation
import Combine
import Photos
import UIKit

final class TimeMachineZeroLatencyViewModel: ObservableObject {
    @Published private(set) var sections: [TimeMachineMonthSection]
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var isLoading: Bool = false

    private let metadataRepository: MetadataRepository
    private let metaStore = TimeMachineMetaStore()
    private let progressStore = TimeMachineProgressStore()
    private let skippedStore = SkippedPhotoStore()
    private let assetIndexStore = AssetIndexStore()
    private let photoRepository = PhotoRepository()
    private let analysisManager: TimeMachineAnalysisManager
    private let analysisCache: PhotoAnalysisCacheStore
    private let thumbnailStore: ThumbnailStore
    private var cancellables: Set<AnyCancellable> = []
    private var latestSnapshot: MetadataSnapshot = .empty
    private let placeholderYears = 4
    private var sessionPreparationTask: Task<SessionPreparationResult, Never>?
    private var sessionPreparationToken: UUID?
    @Published private(set) var coverThumbnails: [String: UIImage] = [:]

    init(
        metadataRepository: MetadataRepository? = nil,
        analysisCache: PhotoAnalysisCacheStore = PhotoAnalysisCacheStore(),
        thumbnailStore: ThumbnailStore = ThumbnailStore()
    ) {
        self.analysisCache = analysisCache
        self.thumbnailStore = thumbnailStore
        self.analysisManager = TimeMachineAnalysisManager(analysisCache: analysisCache)
        if let metadataRepository {
            self.metadataRepository = metadataRepository
        } else {
            self.metadataRepository = MetadataRepository(analysisCache: analysisCache)
        }
        self.sections = TimeMachineZeroLatencyViewModel.makePlaceholderSections(yearsBack: placeholderYears)
        self.metadataRepository.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.latestSnapshot = snapshot
                self.handle(snapshot: snapshot)
            }
            .store(in: &cancellables)
    }

    func onAppear() {
        if authorizationStatus.isAuthorized {
            metadataRepository.bootstrapIfNeeded()
        }
    }

    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                if status.isAuthorized {
                    self?.metadataRepository.bootstrapIfNeeded()
                }
            }
        }
    }

    private func handle(snapshot: MetadataSnapshot) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let authorized = await MainActor.run { self.authorizationStatus.isAuthorized }
            guard authorized else { return }
            await MainActor.run { self.isLoading = true }
            await self.metaStore.rebuild(
                snapshot: snapshot,
                progressStore: self.progressStore,
                skippedStore: self.skippedStore
            )
            let actualSections = await self.metaStore.sections()
            let merged = self.mergeSections(with: actualSections)
            await MainActor.run {
                self.sections = merged
                self.isLoading = false
            }
            await self.preloadCoverThumbnails(for: merged)
        }
    }

    private func makeDetailViewModel(for month: MonthInfo, autoLoad: Bool) -> TimeMachineMonthDetailViewModel {
        TimeMachineMonthDetailViewModel(
            month: month,
            snapshot: latestSnapshot,
            assetIndexStore: assetIndexStore,
            photoRepository: photoRepository,
            analysisManager: analysisManager,
            thumbnailStore: thumbnailStore,
            autoLoad: autoLoad
        )
    }

    func detailViewModel(for month: MonthInfo) -> TimeMachineMonthDetailViewModel {
        makeDetailViewModel(for: month, autoLoad: true)
    }

    func prepareSession(for month: MonthInfo) async -> SessionPreparationResult {
        cancelSessionPreparation()
        let token = UUID()
        sessionPreparationToken = token
        let task = Task<SessionPreparationResult, Never> { [weak self] in
            guard let self else { return .failed }
            return await self.prepareSessionInternal(for: month)
        }
        sessionPreparationTask = task
        let result = await task.value
        if sessionPreparationToken == token {
            sessionPreparationTask = nil
            sessionPreparationToken = nil
        }
        return result
    }

    func cancelSessionPreparation() {
        sessionPreparationTask?.cancel()
        sessionPreparationTask = nil
        sessionPreparationToken = nil
    }

    private func prepareSessionInternal(for month: MonthInfo) async -> SessionPreparationResult {
        let cleanup = await MainActor.run { PhotoCleanupViewModel.shared }
        guard let cleanup else { return .failed }
        let identifiers = await ensureAssetIdentifiers(for: month)
        guard !Task.isCancelled else { return .cancelled }
        guard !identifiers.isEmpty else { return .failed }
        let assets = await photoRepository.assets(for: identifiers)
        guard !Task.isCancelled else { return .cancelled }
        guard !assets.isEmpty else { return .failed }
        return await cleanup.prepareSession(with: assets, month: month)
    }

    private func mergeSections(with actual: [TimeMachineMonthSection]) -> [TimeMachineMonthSection] {
        var map = TimeMachineZeroLatencyViewModel.placeholderMonthMap(yearsBack: placeholderYears)
        for section in actual {
            for month in section.months {
                map[month.id] = month
            }
        }
        return TimeMachineZeroLatencyViewModel.buildSections(from: map)
    }

    private static func makePlaceholderSections(yearsBack: Int) -> [TimeMachineMonthSection] {
        let map = placeholderMonthMap(yearsBack: yearsBack)
        return buildSections(from: map)
    }

    private static func placeholderMonthMap(yearsBack: Int) -> [String: MonthInfo] {
        var map: [String: MonthInfo] = [:]
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let minYear = currentYear - max(yearsBack - 1, 0)
        for year in stride(from: currentYear, through: minYear, by: -1) {
            for month in 1...12 {
                let info = MonthInfo(
                    year: year,
                    month: month,
                    totalPhotos: 0,
                    skippedCount: 0,
                    pendingDeleteCount: 0,
                    confirmedCount: 0
                )
                map[info.id] = info
            }
        }
        return map
    }

    private static func buildSections(from map: [String: MonthInfo]) -> [TimeMachineMonthSection] {
        let grouped = Dictionary(grouping: map.values) { $0.year }
        let sections = grouped.map { year, months in
            let sortedMonths = months.sorted { $0.month < $1.month }
            return TimeMachineMonthSection(year: year, months: sortedMonths)
        }
        return sections.sorted { $0.year > $1.year }
    }

    private func ensureAssetIdentifiers(for month: MonthInfo) async -> [String] {
        let key = monthKey(for: month)
        if let cached = await assetIndexStore.cachedIds(for: key) {
            return cached
        }
        let ids = await resolveAssetIdentifiers(for: month)
        if Task.isCancelled { return [] }
        await assetIndexStore.cache(ids: ids, for: key)
        return ids
    }

    private func resolveAssetIdentifiers(for month: MonthInfo) async -> [String] {
        let snapshot = latestSnapshot
        let key = monthKey(for: month)
        if let moments = snapshot.monthMomentIdentifiers[key], !moments.isEmpty {
            return await photoRepository.assetIdentifiers(forMomentIdentifiers: moments)
        }
        let momentDerived = await photoRepository.assetIdentifiersFromMoments(year: month.year, month: month.month)
        if !momentDerived.isEmpty {
            return momentDerived
        }
        return await photoRepository.assetIdentifiers(forMonth: month.year, month: month.month)
    }

    private func monthKey(for month: MonthInfo) -> String {
        "\(month.year)-\(month.month)"
    }
}

extension TimeMachineZeroLatencyViewModel {
    func coverImage(for monthId: String) -> UIImage? {
        coverThumbnails[monthId]
    }
}

private extension TimeMachineZeroLatencyViewModel {
    func preloadCoverThumbnails(for sections: [TimeMachineMonthSection]) async {
        let months = sections.flatMap { $0.months }
        let assetIds = months.compactMap { $0.coverAssetId }
        await thumbnailStore.preload(assetIds: assetIds, target: .timelineCover)
        for info in months {
            guard let assetId = info.coverAssetId else { continue }
            if await isCoverCached(for: info.id) { continue }
            let image = await thumbnailStore.thumbnail(for: assetId, target: .timelineCover)
            guard let image else { continue }
            await MainActor.run { self.coverThumbnails[info.id] = image }
        }
    }

    func isCoverCached(for monthId: String) async -> Bool {
        await MainActor.run {
            self.coverThumbnails[monthId] != nil
        }
    }
}
