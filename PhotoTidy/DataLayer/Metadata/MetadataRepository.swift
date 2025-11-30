import Foundation
import Photos
import Combine

/// 只读取轻量元数据的仓库：负责首页秒开、时光机月份统计等只读信息
final class MetadataRepository: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var snapshot: MetadataSnapshot = .empty

    private let cacheStore: MetadataCacheStore
    private let analysisCache: PhotoAnalysisCacheStore
    private let processingQueue = DispatchQueue(label: "MetadataRepository.processing", qos: .userInitiated)
    private var fetchResult: PHFetchResult<PHAsset>?
    private var isRefreshing = false
    private var needsBootstrap = true

    init(
        cacheStore: MetadataCacheStore = MetadataCacheStore(),
        analysisCache: PhotoAnalysisCacheStore
    ) {
        self.cacheStore = cacheStore
        self.analysisCache = analysisCache
        super.init()
        Task { [weak self] in
            guard let self else { return }
            let cached = await cacheStore.currentSnapshot()
            await MainActor.run {
                self.snapshot = cached
                self.needsBootstrap = cached.needsBootstrap
            }
        }
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func bootstrapIfNeeded() {
        guard !isRefreshing else { return }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite).isAuthorized else { return }
        isRefreshing = true
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.prepareFetchResultIfNeeded()
            self.generateSnapshot()
            self.isRefreshing = false
        }
    }

    func refresh() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.generateSnapshot()
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let fetchResult,
              let details = changeInstance.changeDetails(for: fetchResult) else { return }
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.fetchResult = details.fetchResultAfterChanges
            self.generateSnapshot()
        }
    }

    private func prepareFetchResultIfNeeded() {
        guard fetchResult == nil else { return }
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchResult = PHAsset.fetchAssets(with: options)
        PHPhotoLibrary.shared().register(self)
    }

    private func generateSnapshot() {
        guard let fetchResult else { return }
        let entries = analysisCache.snapshot()
        let calendar = Calendar.current
        var monthBuckets: [String: MonthAccumulator] = [:]
        var counters = MetadataSnapshot.CategoryCounters.empty

        fetchResult.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate ?? asset.modificationDate else { return }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { return }
            let key = "\(year)-\(month)"
            var bucket = monthBuckets[key] ?? MonthAccumulator(year: year, month: month, total: 0)
            bucket.total += 1
            monthBuckets[key] = bucket

            if asset.mediaType == .video {
                counters.video += 1
            }
            if asset.mediaSubtypes.contains(.photoLive) {
                counters.livePhoto += 1
            }
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                counters.screenshot += 1
            }
            if self.estimatedSize(for: asset) > MetadataRepository.largeFileThreshold {
                counters.largeFile += 1
            }

            if let entry = entries[asset.localIdentifier] {
                if entry.isBlurredOrShaky {
                    counters.blurred += 1
                }
                if entry.isDocumentLike {
                    counters.document += 1
                }
                if entry.similarityGroupId != nil {
                    counters.similar += 1
                }
            }
        }

        let monthTotals = monthBuckets.values
            .sorted { lhs, rhs in
                if lhs.year == rhs.year {
                    return lhs.month > rhs.month
                }
                return lhs.year > rhs.year
            }
            .map { MetadataSnapshot.MonthTotal(year: $0.year, month: $0.month, total: $0.total) }

        let snapshot = MetadataSnapshot(
            schemaVersion: MetadataSnapshot.schemaVersion,
            generatedAt: Date(),
            totalCount: fetchResult.count,
            monthTotals: monthTotals,
            categoryCounters: counters,
            deviceStorageUsage: DeviceStorageUsage.current(),
            cachedAnalysisVersion: PhotoAnalysisCacheEntry.currentVersion,
            needsBootstrap: monthTotals.isEmpty && fetchResult.count == 0
        )

        Task {
            await cacheStore.replace(with: snapshot)
            await MainActor.run {
                self.snapshot = snapshot
                self.needsBootstrap = snapshot.needsBootstrap
            }
        }
    }
}

private extension MetadataRepository {
    struct MonthAccumulator {
        let year: Int
        let month: Int
        var total: Int
    }

    static let largeFileThreshold = 15 * 1_024 * 1_024

    func estimatedSize(for asset: PHAsset) -> Int {
        let resources = PHAssetResource.assetResources(for: asset)
        if let size = resources.first?.value(forKey: "fileSize") as? CLong {
            return Int(size)
        }
        // Fallback: approximate using resolution
        let pixels = asset.pixelWidth * asset.pixelHeight
        return max(pixels * 4, 0)
    }
}

extension PHAuthorizationStatus {
    var isAuthorized: Bool {
        self == .authorized || self == .limited
    }
}
