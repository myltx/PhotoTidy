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
    private var hasScheduledDeferredRefresh = false

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
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite).isAuthorized else { return }
        if needsBootstrap {
            startImmediateRefresh()
        } else {
            scheduleDeferredRefresh()
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
        let counters = buildCategoryCounters(from: fetchResult, entries: entries)
        let previous = snapshot

        let quickSnapshot = MetadataSnapshot(
            schemaVersion: MetadataSnapshot.schemaVersion,
            generatedAt: Date(),
            totalCount: fetchResult.count,
            monthTotals: previous.monthTotals,
            monthMomentIdentifiers: previous.monthMomentIdentifiers,
            monthCoverAssetIds: previous.monthCoverAssetIds,
            monthDateRanges: previous.monthDateRanges,
            categoryCounters: counters,
            deviceStorageUsage: previous.deviceStorageUsage,
            cachedAnalysisVersion: PhotoAnalysisCacheEntry.currentVersion,
            needsBootstrap: previous.needsBootstrap
        )

        Task { @MainActor [quickSnapshot] in
            self.snapshot = quickSnapshot
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let momentData = self.buildMonthMomentData()
            let finalSnapshot = MetadataSnapshot(
                schemaVersion: MetadataSnapshot.schemaVersion,
                generatedAt: Date(),
                totalCount: fetchResult.count,
                monthTotals: momentData.totals,
                monthMomentIdentifiers: momentData.identifiers,
                monthCoverAssetIds: momentData.covers,
                monthDateRanges: momentData.dateRanges,
                categoryCounters: counters,
                deviceStorageUsage: DeviceStorageUsage.current(),
                cachedAnalysisVersion: PhotoAnalysisCacheEntry.currentVersion,
                needsBootstrap: momentData.totals.isEmpty && fetchResult.count == 0
            )
            await self.persist(snapshot: finalSnapshot)
        }
    }

    private func startImmediateRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.prepareFetchResultIfNeeded()
            self.generateSnapshot()
            self.isRefreshing = false
        }
    }

    private func scheduleDeferredRefresh() {
        guard !hasScheduledDeferredRefresh else { return }
        hasScheduledDeferredRefresh = true
        processingQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startImmediateRefresh()
        }
    }
}

private extension MetadataRepository {
    func persist(snapshot: MetadataSnapshot) async {
        await cacheStore.replace(with: snapshot)
        await MainActor.run {
            self.snapshot = snapshot
            self.needsBootstrap = snapshot.needsBootstrap
            if !snapshot.needsBootstrap {
                self.hasScheduledDeferredRefresh = false
            }
        }
    }

    static let largeFileThreshold = 15 * 1_024 * 1_024

    func buildCategoryCounters(from fetchResult: PHFetchResult<PHAsset>, entries: [String: PhotoAnalysisCacheEntry]) -> MetadataSnapshot.CategoryCounters {
        var counters = MetadataSnapshot.CategoryCounters.empty
        let total = fetchResult.count
        let batchSize = 500
        var index = 0
        while index < total {
            autoreleasepool {
                let upper = min(index + batchSize, total)
                for idx in index..<upper {
                    let asset = fetchResult.object(at: idx)
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
            }
            index += batchSize
        }
        return counters
    }

    func buildMonthMomentData() -> (
        totals: [MetadataSnapshot.MonthTotal],
        identifiers: [String: [String]],
        covers: [String: String],
        dateRanges: [String: MetadataSnapshot.MonthDateRange]
    ) {
        struct MomentAggregate {
            var year: Int
            var month: Int
            var total: Int
            var identifiers: [String]
            var coverAssetId: String?
            var earliestDate: Date?
            var latestDate: Date?
        }
        var aggregates: [String: MomentAggregate] = [:]
        let calendar = Calendar.current
        let moments = PHAssetCollection.fetchAssetCollections(with: .moment, subtype: .any, options: nil)
        moments.enumerateObjects { collection, _, _ in
            guard let start = collection.startDate ?? collection.endDate else { return }
            let comps = calendar.dateComponents([.year, .month], from: start)
            guard let year = comps.year, let month = comps.month else { return }
            let key = "\(year)-\(month)"
            var aggregate = aggregates[key] ?? MomentAggregate(year: year, month: month, total: 0, identifiers: [])
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            aggregate.total += assets.count
            aggregate.identifiers.append(collection.localIdentifier)
            if aggregate.coverAssetId == nil, let cover = assets.firstObject?.localIdentifier {
                aggregate.coverAssetId = cover
            }
            if let momentStart = collection.startDate ?? collection.endDate {
                if let existingStart = aggregate.earliestDate {
                    aggregate.earliestDate = min(existingStart, momentStart)
                } else {
                    aggregate.earliestDate = momentStart
                }
            }
            if let momentEnd = collection.endDate ?? collection.startDate {
                if let existingEnd = aggregate.latestDate {
                    aggregate.latestDate = max(existingEnd, momentEnd)
                } else {
                    aggregate.latestDate = momentEnd
                }
            }
            aggregates[key] = aggregate
        }
        let totals = aggregates.values
            .sorted {
                if $0.year == $1.year {
                    return $0.month > $1.month
                }
                return $0.year > $1.year
            }
            .map { MetadataSnapshot.MonthTotal(year: $0.year, month: $0.month, total: $0.total) }

        let identifiers = aggregates.reduce(into: [String: [String]]()) { partialResult, element in
            let key = "\(element.value.year)-\(element.value.month)"
            partialResult[key] = element.value.identifiers
        }
        let covers = aggregates.reduce(into: [String: String]()) { partialResult, element in
            let key = "\(element.value.year)-\(element.value.month)"
            if let cover = element.value.coverAssetId {
                partialResult[key] = cover
            }
        }
        let dateRanges = aggregates.reduce(into: [String: MetadataSnapshot.MonthDateRange]()) { partialResult, element in
            let key = "\(element.value.year)-\(element.value.month)"
            if let start = element.value.earliestDate, let end = element.value.latestDate {
                partialResult[key] = MetadataSnapshot.MonthDateRange(start: start, end: end)
            }
        }
        return (totals, identifiers, covers, dateRanges)
    }

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
