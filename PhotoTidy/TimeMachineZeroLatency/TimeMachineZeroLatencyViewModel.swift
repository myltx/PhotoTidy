import Foundation
import Combine
import Photos

@MainActor
final class TimeMachineZeroLatencyViewModel: ObservableObject {
    @Published private(set) var sections: [TimeMachineMonthSection]
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var isLoading: Bool = false

    private let metadataRepository: MetadataRepository
    private let metaStore = TimeMachineMetaStore()
    private let progressStore = TimeMachineProgressStore()
    private let skippedStore = SkippedPhotoStore()
    private let assetIndexStore = AssetIndexStore()
    private let imageManager = TimeMachineImageManagerWrapper()
    private let photoRepository = PhotoRepository()
    private let analysisManager = TimeMachineAnalysisManager()
    private let analysisCache = PhotoAnalysisCacheStore()
    private var cancellables: Set<AnyCancellable> = []
    private var latestSnapshot: MetadataSnapshot = .empty
    private let placeholderYears = 4

    init() {
        self.metadataRepository = MetadataRepository(analysisCache: analysisCache)
        self.sections = TimeMachineZeroLatencyViewModel.makePlaceholderSections(yearsBack: placeholderYears)
        metadataRepository.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.latestSnapshot = snapshot
                Task { await self.handle(snapshot: snapshot) }
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

    private func handle(snapshot: MetadataSnapshot) async {
        guard authorizationStatus.isAuthorized else { return }
        isLoading = true
        await metaStore.rebuild(
            snapshot: snapshot,
            progressStore: progressStore,
            skippedStore: skippedStore
        )
        let actualSections = await metaStore.sections()
        self.sections = mergeSections(with: actualSections)
        isLoading = false
    }

    private func makeDetailViewModel(for month: MonthInfo, autoLoad: Bool) -> TimeMachineMonthDetailViewModel {
        TimeMachineMonthDetailViewModel(
            month: month,
            snapshot: latestSnapshot,
            assetIndexStore: assetIndexStore,
            photoRepository: photoRepository,
            imageManager: imageManager,
            analysisManager: analysisManager,
            autoLoad: autoLoad
        )
    }

    func detailViewModel(for month: MonthInfo) -> TimeMachineMonthDetailViewModel {
        makeDetailViewModel(for: month, autoLoad: true)
    }

    func prepareSession(for month: MonthInfo) async -> Bool {
        let detailVM = makeDetailViewModel(for: month, autoLoad: false)
        return await detailVM.injectSessionIntoCleanup()
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
}
