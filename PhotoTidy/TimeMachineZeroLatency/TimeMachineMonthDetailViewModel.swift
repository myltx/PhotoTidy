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
    private let imageManager: TimeMachineImageManagerWrapper
    private let analysisManager: TimeMachineAnalysisManager
    private let batchSize = 20
    private var currentOffset = 0
    private var cachedAssetIds: [String] = []
    private let targetSize = CGSize(width: 200, height: 200)

    init(
        month: MonthInfo,
        snapshot: MetadataSnapshot,
        assetIndexStore: AssetIndexStore,
        photoRepository: PhotoRepository,
        imageManager: TimeMachineImageManagerWrapper,
        analysisManager: TimeMachineAnalysisManager,
        autoLoad: Bool = true
    ) {
        self.month = month
        self.snapshot = snapshot
        self.assetIndexStore = assetIndexStore
        self.photoRepository = photoRepository
        self.imageManager = imageManager
        self.analysisManager = analysisManager
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

    func cancelCaching() {
        let batch = currentSliceAssets(count: currentOffset)
        imageManager.stopCaching(assets: batch, targetSize: targetSize)
    }

    private func loadNextBatchIfNeeded() async {
        guard currentOffset < cachedAssetIds.count else { return }
        let batch = await assetIndexStore.batch(for: monthKey, offset: currentOffset, limit: batchSize)
        guard !batch.ids.isEmpty else { return }
        currentOffset += batch.ids.count
        requestThumbnails(for: batch.ids)
    }

    private func requestThumbnails(for ids: [String]) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var fetchedAssets: [PHAsset] = []
        assets.enumerateObjects { [weak self] asset, _, _ in
            guard let self else { return }
            fetchedAssets.append(asset)
            self.imageManager.requestThumbnail(for: asset, targetSize: self.targetSize) { [weak self] image in
                guard let self else { return }
                Task { @MainActor in
                    self.thumbnails[asset.localIdentifier] = image
                }
            }
        }
        imageManager.startCaching(assets: fetchedAssets, targetSize: targetSize)
        Task {
            await analysisManager.enqueue(ids: fetchedAssets.map(\.localIdentifier))
        }
    }

    func ensureAssetIdentifiers() async -> [String] {
        if let cached = await assetIndexStore.cachedIds(for: monthKey) {
            return cached
        }
        let ids = await resolveAssetIdentifiers()
        await assetIndexStore.cache(ids: ids, for: monthKey)
        return ids
    }

    private func resolveAssetIdentifiers() async -> [String] {
        if let moments = snapshot.monthMomentIdentifiers[monthKey], !moments.isEmpty {
            return await photoRepository.assetIdentifiers(forMomentIdentifiers: moments)
        }
        let momentDerived = await photoRepository.assetIdentifiersFromMoments(year: month.year, month: month.month)
        if !momentDerived.isEmpty {
            return momentDerived
        }
        return await photoRepository.assetIdentifiers(forMonth: month.year, month: month.month)
    }

    private var monthKey: String {
        "\(month.year)-\(month.month)"
    }

    private func currentSliceAssets(count: Int) -> [PHAsset] {
        guard count > 0 else { return [] }
        let ids = Array(assetIds.prefix(count))
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var result: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            result.append(asset)
        }
        return result
    }

    func injectSessionIntoCleanup() async -> Bool {
        guard let cleanup = PhotoCleanupViewModel.shared else { return false }
        let identifiers = await ensureAssetIdentifiers()
        guard !identifiers.isEmpty else { return false }
        let assets = await photoRepository.assets(for: identifiers)
        guard !assets.isEmpty else { return false }
        let assetMap = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        let orderedAssets = identifiers.compactMap { assetMap[$0] }
        guard !orderedAssets.isEmpty else { return false }
        return await cleanup.prepareSession(with: orderedAssets, month: month)
    }
}
