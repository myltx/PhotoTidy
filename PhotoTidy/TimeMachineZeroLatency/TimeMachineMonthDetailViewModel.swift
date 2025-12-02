import Foundation
import Combine
import Photos
import UIKit

@MainActor
final class TimeMachineMonthDetailViewModel: ObservableObject {
    @Published var assetIds: [String] = []
    @Published var thumbnails: [String: UIImage] = [:]
    @Published var isLoading: Bool = false

    private let month: MonthInfo
    private let snapshot: MetadataSnapshot
    private let assetIndexStore: AssetIndexStore
    private let photoRepository: PhotoRepository
    private let analysisManager: TimeMachineAnalysisManager
    private let thumbnailStore: ThumbnailStore
    private let batchSize = 20
    private var currentOffset = 0
    private var cachedAssetIds: [String] = []

    init(
        month: MonthInfo,
        snapshot: MetadataSnapshot,
        assetIndexStore: AssetIndexStore,
        photoRepository: PhotoRepository,
        analysisManager: TimeMachineAnalysisManager,
        thumbnailStore: ThumbnailStore,
        autoLoad: Bool = true
    ) {
        self.month = month
        self.snapshot = snapshot
        self.assetIndexStore = assetIndexStore
        self.photoRepository = photoRepository
        self.analysisManager = analysisManager
        self.thumbnailStore = thumbnailStore
        if autoLoad {
            Task { await loadInitialIds() }
        }
    }

    func loadInitialIds() async {
        isLoading = true
        cachedAssetIds = await ensureAssetIdentifiers()
        await MainActor.run {
            self.assetIds = cachedAssetIds
            self.isLoading = false
        }
        await loadNextBatchIfNeeded()
    }

    func loadMoreIfNeeded(currentId: String) {
        guard let index = assetIds.firstIndex(of: currentId) else { return }
        if index >= currentOffset - 5 {
            Task { await loadNextBatchIfNeeded() }
        }
    }

    private func loadNextBatchIfNeeded() async {
        guard currentOffset < cachedAssetIds.count else { return }
        let batch = await assetIndexStore.batch(for: monthKeyString, offset: currentOffset, limit: batchSize)
        guard !batch.ids.isEmpty else { return }
        currentOffset += batch.ids.count
        requestThumbnails(for: batch.ids)
    }

    private func requestThumbnails(for ids: [String]) {
        Task { [weak self] in
            guard let self else { return }
            await thumbnailStore.preload(assetIds: ids, target: .monthDetail)
            for id in ids {
                if let image = await thumbnailStore.thumbnail(for: id, target: .monthDetail) {
                    await MainActor.run {
                        self.thumbnails[id] = image
                    }
                }
            }
            await analysisManager.enqueue(ids: ids)
        }
    }

    func ensureAssetIdentifiers() async -> [String] {
        if let cached = await assetIndexStore.cachedIds(for: monthKeyString) {
            return cached
        }
        let ids = await resolveAssetIdentifiers()
        await assetIndexStore.cache(ids: ids, for: monthKeyString)
        return ids
    }

    private func resolveAssetIdentifiers() async -> [String] {
        if let moments = snapshot.monthMomentIdentifiers[monthKeyString], !moments.isEmpty {
            return await photoRepository.assetIdentifiers(forMomentIdentifiers: moments)
        }
        let momentDerived = await photoRepository.assetIdentifiersFromMoments(year: month.year, month: month.month)
        if !momentDerived.isEmpty {
            return momentDerived
        }
        return await photoRepository.assetIdentifiers(forMonth: month.year, month: month.month)
    }

    private var monthKeyString: String {
        "\(month.year)-\(month.month)"
    }
}
