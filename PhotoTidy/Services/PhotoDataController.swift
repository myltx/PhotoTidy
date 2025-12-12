import Foundation
import Photos
import UIKit
import Vision

/// 数据编排层（当前阶段聚焦：加载资产、应用缓存、优先级分析、节流写盘）
/// UI 仍由 ViewModel 管理会话/导航，但所有分析与持久化由 controller 统一处理。
@MainActor
final class PhotoDataController: NSObject {
    struct Snapshot {
        let items: [PhotoItem]
        let monthAssetTotals: [String: Int]
        let timeMachineSnapshots: [String: TimeMachineMonthProgress]
        let skippedPhotoRecords: [SkippedPhotoRecord]
        let smartCleanupProgress: SmartCleanupProgress?
    }

    var onSnapshotChange: ((Snapshot) -> Void)?
    var onAnalysisStateChange: ((AnalysisState) -> Void)?

    func currentSnapshot() -> Snapshot {
        Snapshot(
            items: items,
            monthAssetTotals: monthAssetTotals,
            timeMachineSnapshots: timeMachineSnapshots,
            skippedPhotoRecords: skippedPhotoRecords,
            smartCleanupProgress: smartCleanupProgress
        )
    }

    private let analysisCache: PhotoAnalysisRepository
    private let userStateRepo: PhotoUserStateRepository
    private let analysisScheduler: AnalysisScheduler
    private let metaStore: AnalysisDashboardMetaStore
    private let analysisBatchSize = 50
    private let analysisFlushCount = 100
    private let analysisFlushInterval: TimeInterval = 1.5

    private let imageManager = PHCachingImageManager()
    private var loadedAssetIdentifiers: Set<String> = []

    private var items: [PhotoItem] = []
    private var monthAssetTotals: [String: Int] = [:]
    private var timeMachineSnapshots: [String: TimeMachineMonthProgress] = [:]
    private var skippedPhotoRecords: [SkippedPhotoRecord] = []
    private var smartCleanupProgress: SmartCleanupProgress?

    private var analysisWorkerTask: Task<Void, Never>?
    private var analysisIsRunning = false

    init(
        analysisCache: PhotoAnalysisRepository,
        userStateRepo: PhotoUserStateRepository,
        metaStore: AnalysisDashboardMetaStore = AnalysisDashboardMetaStore(),
        analysisScheduler: AnalysisScheduler = AnalysisScheduler()
    ) {
        self.analysisCache = analysisCache
        self.userStateRepo = userStateRepo
        self.metaStore = metaStore
        self.analysisScheduler = analysisScheduler
        self.smartCleanupProgress = userStateRepo.loadSmartProgress()
        self.skippedPhotoRecords = userStateRepo.skippedRecords()
        super.init()
        refreshTimeMachineSnapshots()
        publishSnapshot()
    }

    // MARK: - External Inputs

    func resetPagingState() {
        loadedAssetIdentifiers.removeAll()
        analysisIsRunning = false
        analysisWorkerTask?.cancel()
        analysisWorkerTask = nil
        Task.detached { [analysisScheduler] in
            await analysisScheduler.reset()
        }
        items = []
        publishSnapshot()
    }

    func handleFetchResultUpdate(_ fetchResult: PHFetchResult<PHAsset>) {
        Task.detached { [analysisCache] in
            var identifiers: Set<String> = []
            fetchResult.enumerateObjects { asset, _, _ in
                identifiers.insert(asset.localIdentifier)
            }
            analysisCache.pruneMissingEntries(keeping: identifiers)
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var counts: [String: Int] = [:]
            let calendar = Calendar.current
            fetchResult.enumerateObjects { asset, _, _ in
                guard let date = asset.creationDate ?? asset.modificationDate else { return }
                let comps = calendar.dateComponents([.year, .month], from: date)
                guard let year = comps.year, let month = comps.month else { return }
                let key = "\(year)-\(month)"
                counts[key, default: 0] += 1
            }
            await MainActor.run {
                self.monthAssetTotals = counts
                self.publishSnapshot()
            }
        }
    }

    func updateMonthAssetTotals(_ totals: [String: Int]) {
        monthAssetTotals = totals
        publishSnapshot()
    }

    /// PhotoKit 变更增量应用：重建当前已加载前缀顺序，并为新增项入队分析。
    func applyLibraryChange(_ details: PHFetchResultChangeDetails<PHAsset>) {
        guard details.hasIncrementalChanges else {
            resetPagingState()
            return
        }

        let afterChanges = details.fetchResultAfterChanges
        let loadedCount = items.count
        let prefixCount = min(loadedCount, afterChanges.count)
        if prefixCount == 0 {
            items = []
            loadedAssetIdentifiers.removeAll()
            publishSnapshot()
            return
        }

        let cacheEntries = analysisCache.snapshot()
        let existingMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var newItems: [PhotoItem] = []
        newItems.reserveCapacity(prefixCount)
        var inserted: [PHAsset] = []

        for index in 0..<prefixCount {
            let asset = afterChanges.object(at: index)
            let id = asset.localIdentifier
            let estimatedSize = assetResourceSize(for: asset)

            if let existing = existingMap[id] {
                var item = existing
                item = PhotoItem(
                    id: id,
                    asset: asset,
                    pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                    fileSize: estimatedSize,
                    creationDate: asset.creationDate,
                    isVideo: asset.mediaType == .video,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                    pHash: existing.pHash,
                    blurScore: existing.blurScore,
                    exposureIsBad: existing.exposureIsBad,
                    isBlurredOrShaky: existing.isBlurredOrShaky,
                    isDocumentLike: existing.isDocumentLike,
                    isTextImage: existing.isTextImage,
                    isLargeFile: existing.isLargeFile,
                    similarGroupId: existing.similarGroupId,
                    similarityKind: existing.similarityKind,
                    assetType: existing.assetType,
                    markedForDeletion: existing.markedForDeletion
                )

                if let entry = cacheEntries[id],
                   entry.version == PhotoAnalysisCacheEntry.currentVersion,
                   entry.fileSize == estimatedSize {
                    applyCachedEntry(entry, to: &item)
                }
                newItems.append(item)
            } else {
                var item = PhotoItem(
                    id: id,
                    asset: asset,
                    pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                    fileSize: estimatedSize,
                    creationDate: asset.creationDate,
                    isVideo: asset.mediaType == .video,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                    pHash: nil,
                    blurScore: nil,
                    exposureIsBad: false,
                    isBlurredOrShaky: false,
                    isDocumentLike: false,
                    isTextImage: false,
                    isLargeFile: estimatedSize > 10 * 1024 * 1024,
                    similarGroupId: nil,
                    similarityKind: nil,
                    assetType: nil,
                    markedForDeletion: false
                )
                if let entry = cacheEntries[id],
                   entry.version == PhotoAnalysisCacheEntry.currentVersion,
                   entry.fileSize == item.fileSize {
                    applyCachedEntry(entry, to: &item)
                }
                var tmp = [item]
                restoreSelectionStates(in: &tmp)
                newItems.append(tmp[0])
                inserted.append(asset)
            }
        }

        items = newItems
        loadedAssetIdentifiers = Set(newItems.map(\.id))
        publishSnapshot()

        if !inserted.isEmpty {
            let insertedIds = Set(inserted.map(\.localIdentifier))
            let insertedItems = newItems.filter { insertedIds.contains($0.id) }
            enqueueAnalysis(for: insertedItems)
        }
    }

    func handleLoadedAssets(_ assets: [PHAsset]) {
        ingestAssets(assets)
    }

    /// ViewModel 在会话/可见项变化时提升优先级
    func elevateAnalysisPriority(for candidates: [PhotoItem]) {
        guard !candidates.isEmpty else { return }
        let cacheSnapshot = analysisCache.snapshot()
        let ids = candidates.prefix(400).compactMap { item -> String? in
            needsAnalysis(item, cacheSnapshot: cacheSnapshot) ? item.id : nil
        }
        guard !ids.isEmpty else { return }
        Task.detached { [analysisScheduler] in
            await analysisScheduler.enqueue(ids, priority: .high)
        }
        startAnalysisWorkerIfNeeded()
    }

    // MARK: - User State APIs（供 ViewModel 调用）

    func updateSmartCleanupProgress(_ progress: SmartCleanupProgress?) {
        smartCleanupProgress = progress
        userStateRepo.saveSmartProgress(progress)
        publishSnapshot()
    }

    func refreshSkippedRecords() {
        skippedPhotoRecords = userStateRepo.skippedRecords()
        publishSnapshot()
    }

    func refreshTimeMachineSnapshots() {
        let progresses = userStateRepo.allMonthProgresses()
        var snapshot: [String: TimeMachineMonthProgress] = [:]
        progresses.forEach { snapshot[$0.key] = $0 }
        timeMachineSnapshots = snapshot
        publishSnapshot()
    }

    func setPhotoSelected(_ photoId: String, year: Int, month: Int, selected: Bool) {
        userStateRepo.setPhotoSelected(photoId: photoId, year: year, month: month, selected: selected)
        refreshTimeMachineSnapshots()
    }

    func confirmPhoto(_ photoId: String, year: Int, month: Int) {
        userStateRepo.confirmPhoto(photoId: photoId, year: year, month: month)
        refreshTimeMachineSnapshots()
    }

    func removePhotoRecords(_ photoId: String, year: Int, month: Int) {
        userStateRepo.removePhotoRecords(photoId: photoId, year: year, month: month)
        refreshTimeMachineSnapshots()
    }

    func resetAllTimeMachine() {
        userStateRepo.resetAllTimeMachine()
        refreshTimeMachineSnapshots()
    }

    func recordSkipped(photoId: String, source: SkippedPhotoSource) {
        userStateRepo.recordSkipped(photoId: photoId, source: source)
        refreshSkippedRecords()
    }

    func markSkippedProcessed(ids: [String]) {
        userStateRepo.markSkippedProcessed(ids: ids)
        refreshSkippedRecords()
    }

    func removeSkipped(ids: [String]) {
        userStateRepo.removeSkipped(ids: ids)
        refreshSkippedRecords()
    }

    func clearSkipped() {
        userStateRepo.clearSkipped()
        refreshSkippedRecords()
    }

    func removeAnalysisEntries(ids: [String]) {
        analysisCache.removeEntries(for: ids)
    }

    func setMarkedForDeletion(photoId: String, flag: Bool) {
        guard let index = items.firstIndex(where: { $0.id == photoId }) else { return }
        items[index].markedForDeletion = flag
        publishSnapshot()
    }

    func clearMarkedForDeletion(photoIds: [String]) {
        guard !photoIds.isEmpty else { return }
        var changed = false
        for id in photoIds {
            if let idx = items.firstIndex(where: { $0.id == id }), items[idx].markedForDeletion {
                items[idx].markedForDeletion = false
                changed = true
            }
        }
        if changed {
            publishSnapshot()
        }
    }

    func removeItems(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        loadedAssetIdentifiers.subtract(ids)
        publishSnapshot()
    }

    // MARK: - Internals: Ingest & Analysis

    private func ingestAssets(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let cacheEntries = analysisCache.snapshot()
        var incoming: [PhotoItem] = []

        for asset in assets {
            let id = asset.localIdentifier
            if loadedAssetIdentifiers.contains(id) { continue }
            loadedAssetIdentifiers.insert(id)
            let estimatedSize = assetResourceSize(for: asset)
            var item = PhotoItem(
                id: id,
                asset: asset,
                pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                fileSize: estimatedSize,
                creationDate: asset.creationDate,
                isVideo: asset.mediaType == .video,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                pHash: nil,
                blurScore: nil,
                exposureIsBad: false,
                isBlurredOrShaky: false,
                isDocumentLike: false,
                isTextImage: false,
                isLargeFile: estimatedSize > 10 * 1024 * 1024,
                similarGroupId: nil,
                similarityKind: nil,
                assetType: nil,
                markedForDeletion: false
            )

            if let entry = cacheEntries[id],
               entry.version == PhotoAnalysisCacheEntry.currentVersion,
               entry.fileSize == item.fileSize {
                applyCachedEntry(entry, to: &item)
            }

            incoming.append(item)
        }

        guard !incoming.isEmpty else { return }
        restoreSelectionStates(in: &incoming)
        items.append(contentsOf: incoming)
        publishSnapshot()
        enqueueAnalysis(for: incoming)
    }

    private func restoreSelectionStates(in items: inout [PhotoItem]) {
        for index in items.indices {
            guard
                let comps = monthComponents(for: items[index]),
                let progress = userStateRepo.monthProgress(year: comps.year, month: comps.month)
            else { continue }
            if progress.selectedPhotoIds.contains(items[index].id) {
                items[index].markedForDeletion = true
            }
        }
    }

    private func enqueueAnalysis(for incoming: [PhotoItem]) {
        let cacheSnapshot = analysisCache.snapshot()
        let needIds = incoming.compactMap { item -> String? in
            needsAnalysis(item, cacheSnapshot: cacheSnapshot) ? item.id : nil
        }
        guard !needIds.isEmpty else { return }
        Task.detached { [analysisScheduler] in
            await analysisScheduler.enqueue(needIds, priority: .normal)
        }
        startAnalysisWorkerIfNeeded()
    }

    private func needsAnalysis(_ item: PhotoItem, cacheSnapshot: [String: PhotoAnalysisCacheEntry]) -> Bool {
        if let entry = cacheSnapshot[item.id],
           entry.version == PhotoAnalysisCacheEntry.currentVersion,
           entry.fileSize == item.fileSize {
            return false
        }
        if item.blurScore == nil { return true }
        if !item.isVideo && item.pHash == nil { return true }
        return false
    }

    private func startAnalysisWorkerIfNeeded() {
        guard !analysisIsRunning else { return }
        analysisIsRunning = true
        onAnalysisStateChange?(.analyzing(progress: "准备中"))
        analysisWorkerTask = Task.detached(priority: .utility) { [weak self] in
            await self?.runAnalysisWorker()
        }
    }

    private func runAnalysisWorker() async {
        var dirtyEntries: [PhotoAnalysisCacheEntry] = []
        var runEntriesById: [String: PhotoAnalysisCacheEntry] = [:]
        var lastFlushAt = Date()

        let analysisService = ImageAnalysisService.shared
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .exact
        requestOptions.isNetworkAccessAllowed = true
        let targetSize = CGSize(width: 256, height: 256)

        while true {
            let batchIds = await analysisScheduler.nextBatch(limit: analysisBatchSize)
            if batchIds.isEmpty { break }
            await MainActor.run { [weak self] in
                self?.onAnalysisStateChange?(.analyzing(progress: "\(batchIds.count) 张"))
            }

            let itemsById = await MainActor.run { [weak self] in
                Dictionary(uniqueKeysWithValues: (self?.items ?? []).map { ($0.id, $0) })
            }
            let batchItems = batchIds.compactMap { itemsById[$0] }
            guard !batchItems.isEmpty else { continue }
            let cacheSnapshot = analysisCache.snapshot()

            var batchEntries: [PhotoAnalysisCacheEntry] = []
            batchEntries.reserveCapacity(batchItems.count)

            for item in batchItems {
                if runEntriesById[item.id] != nil { continue }
                if !needsAnalysis(item, cacheSnapshot: cacheSnapshot) { continue }

                autoreleasepool {
                    var thumbnail: UIImage?
                    let semaphore = DispatchSemaphore(value: 0)
                    imageManager.requestImage(
                        for: item.asset,
                        targetSize: targetSize,
                        contentMode: .aspectFill,
                        options: requestOptions
                    ) { image, _ in
                        thumbnail = image
                        semaphore.signal()
                    }
                    semaphore.wait()

                    var blurScore: Double? = nil
                    var exposureBad = false
                    var isBlurredOrShaky = false
                    var pHash: UInt64? = nil
                    var featureData: Data? = nil

                    if let image = thumbnail {
                        blurScore = analysisService.computeBlurScore(for: image) ?? 0
                        exposureBad = analysisService.isExposureBad(for: image)
                        isBlurredOrShaky = (blurScore ?? 0) < 0.04 || ((blurScore ?? 0) < 0.07 && exposureBad)
                        if !item.isVideo {
                            let fp = analysisService.featurePrint(for: image)
                            featureData = archiveFeaturePrint(fp)
                            pHash = analysisService.perceptualHash(for: image)
                        }
                    }

                    let entry = PhotoAnalysisCacheEntry(
                        localIdentifier: item.id,
                        fileSize: item.fileSize,
                        isScreenshot: item.isScreenshot,
                        isDocumentLike: item.isDocumentLike,
                        isTextImage: item.isTextImage,
                        blurScore: blurScore,
                        isBlurredOrShaky: isBlurredOrShaky,
                        exposureIsBad: exposureBad,
                        pHash: pHash,
                        featurePrintData: featureData,
                        similarityGroupId: nil,
                        similarityKind: nil
                    )
                    batchEntries.append(entry)
                }
            }

            if !batchEntries.isEmpty {
                for entry in batchEntries {
                    runEntriesById[entry.localIdentifier] = entry
                }
                dirtyEntries.append(contentsOf: batchEntries)
            }

            let shouldFlushByCount = dirtyEntries.count >= analysisFlushCount
            let shouldFlushByTime = Date().timeIntervalSince(lastFlushAt) >= analysisFlushInterval
            if shouldFlushByCount || shouldFlushByTime {
                await flushDirtyEntries(&dirtyEntries)
                lastFlushAt = Date()
            }
        }

        if !dirtyEntries.isEmpty {
            await flushDirtyEntries(&dirtyEntries)
        }

        await finalizeAnalysisRun(using: runEntriesById)

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.analysisIsRunning = false
            self.onAnalysisStateChange?(.idle)
        }

        let pending = await analysisScheduler.hasPending()
        if pending {
            await MainActor.run { [weak self] in
                self?.startAnalysisWorkerIfNeeded()
            }
        }
    }

    private func flushDirtyEntries(_ dirtyEntries: inout [PhotoAnalysisCacheEntry]) async {
        let entries = dirtyEntries
        dirtyEntries.removeAll()
        analysisCache.update(entries: entries)

        await MainActor.run { [weak self] in
            guard let self else { return }
            var updatedItems = self.items
            for entry in entries {
                if let idx = updatedItems.firstIndex(where: { $0.id == entry.localIdentifier }) {
                    var item = updatedItems[idx]
                    self.applyCachedEntry(entry, to: &item)
                    updatedItems[idx] = item
                }
            }
            self.items = updatedItems
            self.publishSnapshot()
        }
    }

    private func finalizeAnalysisRun(using runEntriesById: [String: PhotoAnalysisCacheEntry]) async {
        let snapshotItems: [PhotoItem] = await MainActor.run { [weak self] in
            self?.items ?? []
        }
        guard !snapshotItems.isEmpty else { return }

        let cacheSnapshot = analysisCache.snapshot()
        var analyzedItems = snapshotItems
        let total = analyzedItems.count
        var featurePrints: [VNFeaturePrintObservation?] = Array(repeating: nil, count: total)
        var pHashes: [UInt64?] = Array(repeating: nil, count: total)

        for i in 0..<total {
            let item = analyzedItems[i]
            analyzedItems[i].similarGroupId = nil
            analyzedItems[i].similarityKind = nil

            if let newEntry = runEntriesById[item.id] {
                featurePrints[i] = unarchiveFeaturePrint(from: newEntry.featurePrintData)
                pHashes[i] = newEntry.pHash
            } else if let entry = cacheSnapshot[item.id],
                      entry.version == PhotoAnalysisCacheEntry.currentVersion,
                      entry.fileSize == item.fileSize {
                featurePrints[i] = unarchiveFeaturePrint(from: entry.featurePrintData)
                pHashes[i] = entry.pHash
            }
        }

        processSimilarGroups(analyzedItems: &analyzedItems, pHashes: pHashes)
        let fullEntries = buildCacheEntries(from: analyzedItems, featurePrints: featurePrints, pHashes: pHashes)
        analysisCache.update(entries: fullEntries)
        await metaStore.update(lastUpdated: Date(), lastSimilarityRun: Date())

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.items = analyzedItems
            self.publishSnapshot()
        }
    }

    private func processSimilarGroups(analyzedItems: inout [PhotoItem], pHashes: [UInt64?]) {
        let total = analyzedItems.count
        guard total > 1 else { return }
        let analysisService = ImageAnalysisService.shared
        let indices = Array(0..<total).sorted { lhs, rhs in
            let d1 = analyzedItems[lhs].creationDate ?? .distantPast
            let d2 = analyzedItems[rhs].creationDate ?? .distantPast
            return d1 < d2
        }

        let timeWindow: TimeInterval = 3.0
        var buckets: [[Int]] = []
        var current: [Int] = []
        var bucketStart: Date?

        for idx in indices {
            guard let date = analyzedItems[idx].creationDate else { continue }
            if current.isEmpty {
                current = [idx]
                bucketStart = date
            } else if let start = bucketStart, date.timeIntervalSince(start) <= timeWindow {
                current.append(idx)
            } else {
                if current.count > 1 { buckets.append(current) }
                current = [idx]
                bucketStart = date
            }
        }
        if current.count > 1 { buckets.append(current) }

        var globalGroupId = 0
        let pHashThreshold = 10

        for bucket in buckets {
            var used = Set<Int>()
            for i in 0..<bucket.count {
                let idxI = bucket[i]
                if used.contains(idxI) { continue }
                guard let h1 = pHashes[idxI] else { continue }

                var group: [Int] = [idxI]
                used.insert(idxI)

                for j in (i + 1)..<bucket.count {
                    let idxJ = bucket[j]
                    if used.contains(idxJ) { continue }
                    guard let h2 = pHashes[idxJ] else { continue }
                    let distance = analysisService.hammingDistance(h1, h2)
                    if distance < pHashThreshold {
                        group.append(idxJ)
                        used.insert(idxJ)
                    }
                }

                if group.count > 1 {
                    globalGroupId += 1
                    for idx in group {
                        analyzedItems[idx].similarGroupId = globalGroupId
                        analyzedItems[idx].similarityKind = .similar
                    }
                }
            }
        }
    }

    private func buildCacheEntries(
        from analyzedItems: [PhotoItem],
        featurePrints: [VNFeaturePrintObservation?],
        pHashes: [UInt64?]
    ) -> [PhotoAnalysisCacheEntry] {
        guard analyzedItems.count == featurePrints.count,
              analyzedItems.count == pHashes.count else {
            return []
        }
        return analyzedItems.enumerated().map { index, item in
            PhotoAnalysisCacheEntry(
                localIdentifier: item.id,
                fileSize: item.fileSize,
                isScreenshot: item.isScreenshot,
                isDocumentLike: item.isDocumentLike,
                isTextImage: item.isTextImage,
                blurScore: item.blurScore,
                isBlurredOrShaky: item.isBlurredOrShaky,
                exposureIsBad: item.exposureIsBad,
                pHash: pHashes[index],
                featurePrintData: archiveFeaturePrint(featurePrints[index]),
                similarityGroupId: item.similarGroupId,
                similarityKind: item.similarityKind?.rawValue
            )
        }
    }

    private func archiveFeaturePrint(_ observation: VNFeaturePrintObservation?) -> Data? {
        guard let observation else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    private func unarchiveFeaturePrint(from data: Data?) -> VNFeaturePrintObservation? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    private func applyCachedEntry(_ entry: PhotoAnalysisCacheEntry, to item: inout PhotoItem) {
        item.isScreenshot = entry.isScreenshot
        item.isDocumentLike = entry.isDocumentLike
        item.isTextImage = entry.isTextImage
        item.blurScore = entry.blurScore
        item.isBlurredOrShaky = entry.isBlurredOrShaky
        item.exposureIsBad = entry.exposureIsBad
        item.pHash = entry.pHash
        item.similarGroupId = entry.similarityGroupId
        if let kindRaw = entry.similarityKind {
            item.similarityKind = SimilarityGroupKind(rawValue: kindRaw)
        } else {
            item.similarityKind = nil
        }
        item.isLargeFile = item.fileSize > 15 * 1024 * 1024
    }

    private func monthComponents(for item: PhotoItem) -> (year: Int, month: Int)? {
        guard let date = item.creationDate else { return nil }
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        return (year, month)
    }

    private func assetResourceSize(for asset: PHAsset) -> Int {
        let resources = PHAssetResource.assetResources(for: asset)
        if asset.mediaType == .video {
            if let video = resources.first(where: { $0.type == .video }),
               let size = video.value(forKey: "fileSize") as? Int {
                return size
            }
        }
        if let primary = resources.first,
           let size = primary.value(forKey: "fileSize") as? Int {
            return size
        }
        return max(asset.pixelWidth * asset.pixelHeight * 4, 0)
    }

    private func publishSnapshot() {
        onSnapshotChange?(Snapshot(
            items: items,
            monthAssetTotals: monthAssetTotals,
            timeMachineSnapshots: timeMachineSnapshots,
            skippedPhotoRecords: skippedPhotoRecords,
            smartCleanupProgress: smartCleanupProgress
        ))
    }
}
