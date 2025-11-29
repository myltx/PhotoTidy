import SwiftUI
import Combine
import Photos
import Vision

final class PhotoCleanupViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    // MARK: - Properties
    
    // Status
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var isLoading: Bool = false
    @Published var isAnalyzing: Bool = false
    @Published var analysisProgress: Double = 0
    @Published var selectedTheme: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "app_theme") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "app_theme")
        }
    }

    // Data
    @Published var items: [PhotoItem] = [] {
        didSet {
            rebuildMonthStatuses(with: items)
        }
    }
    @Published var sessionItems: [PhotoItem] = []
    @Published var lastFreedSpace: Int = 0
    @Published var lastDeletedItemsCount: Int = 0
    @Published var deviceStorageUsage: DeviceStorageUsage = .empty
    @Published private(set) var monthStatuses: [String: MonthStatus] = [:]
    
    // Navigation & Session State
    @Published var currentTab: AppView = .dashboard
    @Published var isShowingCleaner: Bool = false
    @Published var activeDetail: DashboardDetail?
    @Published var isShowingSuccessSummary: Bool = false
    
    @Published var currentFilter: CleanupFilterMode = .all
    @Published var currentIndex: Int = 0
    private var activeMonthContext: (year: Int, month: Int)?

    // Services
    let imageManager = PHCachingImageManager()
    private let progressStore: CleanupProgressStore
    private let analysisCache: PhotoAnalysisCacheStore
    private var assetsFetchResult: PHFetchResult<PHAsset>?
    private var cancellable: AnyCancellable?

    // MARK: - Computed Properties
    
    // Session Items
    var currentItem: PhotoItem? { sessionItems[safe: currentIndex] }
    var nextItem: PhotoItem? { sessionItems[safe: currentIndex + 1] }
    var thirdItem: PhotoItem? { sessionItems[safe: currentIndex + 2] }
    
    struct CleanupResumeInfo {
        let lastStopDate: Date
        let pendingDeletionCount: Int
    }
    
    var cleanupResumeInfo: CleanupResumeInfo? {
        let progresses = progressStore.allProgresses()
        guard !progresses.isEmpty else { return nil }
        let sorted = progresses.sorted {
            if $0.year == $1.year {
                return $0.month > $1.month
            }
            return $0.year > $1.year
        }
        for progress in sorted {
            guard progress.processedCount > 0 else { continue }
            let monthItems = monthItems(year: progress.year, month: progress.month)
            guard !monthItems.isEmpty else { continue }
            let index = min(progress.processedCount, monthItems.count) - 1
            guard index >= 0 else { continue }
            if let date = monthItems[index].creationDate {
                return CleanupResumeInfo(
                    lastStopDate: date,
                    pendingDeletionCount: pendingDeletionItems.count
                )
            }
        }
        return nil
    }

    // Dashboard Stats
    var similarItemsCount: Int { items.filter { $0.similarGroupId != nil }.count }
    var blurredItemsCount: Int { items.filter { $0.isBlurredOrShaky }.count }
    var screenshotItemsCount: Int { items.filter { $0.isScreenshot || $0.isDocumentLike }.count }
    var largeFilesSize: Int { items.filter { $0.isLargeFile }.map { $0.fileSize }.reduce(0, +) }

    // Pending Deletion
    var pendingDeletionItems: [PhotoItem] { items.filter { $0.markedForDeletion }.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) } }
    var pendingDeletionTotalSize: Int { pendingDeletionItems.map { $0.fileSize }.reduce(0, +) }

    // MARK: - Initialization
    
    init(
        progressStore: CleanupProgressStore = .shared,
        analysisCache: PhotoAnalysisCacheStore = PhotoAnalysisCacheStore()
    ) {
        self.analysisCache = analysisCache
        self.progressStore = progressStore
        super.init()
        PHPhotoLibrary.shared().register(self)
        refreshDeviceStorageUsage()
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadAssets()
        }
        
        cancellable = NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.updateAuthorizationStatus()
                self?.refreshDeviceStorageUsage()
            }
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    // MARK: - Status Updates
    
    private func updateAuthorizationStatus() {
        DispatchQueue.main.async {
            let oldStatus = self.authorizationStatus
            let newStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            self.authorizationStatus = newStatus

            if newStatus != oldStatus && (newStatus == .authorized || newStatus == .limited) {
                self.loadAssets()
            }
        }
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let fetchResult = assetsFetchResult,
              changeInstance.changeDetails(for: fetchResult) != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.loadAssets()
        }
    }
    
    // MARK: - Navigation
    
    func showCleaner(filter: CleanupFilterMode) {
        activeMonthContext = nil
        updateSessionItems(for: filter)
        isShowingCleaner = true
    }

    func showCleaner(forMonth year: Int, month: Int) {
        activeMonthContext = (year, month)
        rebuildMonthSession(year: year, month: month)
        isShowingCleaner = true
    }
    
    func hideCleaner() {
        isShowingCleaner = false
        activeMonthContext = nil
    }

    func showDetail(_ detail: DashboardDetail) {
        activeDetail = detail
    }

    func dismissDetail() {
        activeDetail = nil
    }

    // MARK: - Session Management

    func updateSessionItems(for filter: CleanupFilterMode) {
        self.currentFilter = filter
        let notDeleted = items.filter { !$0.markedForDeletion }
        
        switch filter {
        case .all: sessionItems = notDeleted
        case .similar: sessionItems = notDeleted.filter { $0.similarGroupId != nil }
        case .blurred: sessionItems = notDeleted.filter { $0.isBlurredOrShaky }
        case .screenshots: sessionItems = notDeleted.filter { $0.isScreenshot || $0.isDocumentLike }
        case .documents: sessionItems = notDeleted.filter { $0.isDocumentLike }
        case .large: sessionItems = notDeleted.filter { $0.isLargeFile }
        }
        
        currentIndex = 0
    }

    func refreshSession() {
        if let context = activeMonthContext {
            rebuildMonthSession(year: context.year, month: context.month)
        } else {
            updateSessionItems(for: self.currentFilter)
        }
    }

    // MARK: - Data Loading & Analysis

    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorizationStatus = newStatus
                if newStatus == .authorized || newStatus == .limited {
                    self.loadAssets()
                }
            }
        }
    }

    func loadAssets() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedItems: [PhotoItem] = []
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let allResult = PHAsset.fetchAssets(with: fetchOptions)
            DispatchQueue.main.async {
                self.assetsFetchResult = allResult
            }
            var currentIdentifiers: Set<String> = []
            allResult.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                let fileSize = (resources.first?.value(forKey: "fileSize") as? Int) ?? 0
                currentIdentifiers.insert(asset.localIdentifier)
                let item = PhotoItem(
                    id: asset.localIdentifier,
                    asset: asset,
                    pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                    fileSize: fileSize,
                    creationDate: asset.creationDate,
                    isVideo: asset.mediaType == .video,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                    pHash: nil,
                    blurScore: nil,
                    exposureIsBad: false,
                    isBlurredOrShaky: false,
                    isDocumentLike: false,
                    isTextImage: false,
                    isLargeFile: fileSize > 10 * 1024 * 1024,
                    similarGroupId: nil,
                    similarityKind: nil,
                    assetType: nil,
                    markedForDeletion: false
                )
                loadedItems.append(item)
            }
            self.analysisCache.pruneMissingEntries(keeping: currentIdentifiers)
            
            DispatchQueue.main.async {
                var restoredItems = loadedItems
                self.restoreSelectionStates(in: &restoredItems)
                self.applyCachedAnalysis(to: &restoredItems)
                self.items = restoredItems
                self.isLoading = false
                self.updateSessionItems(for: .all)
                self.analyzeAllItemsInBackground()
            }
        }
    }

    private func analyzeAllItemsInBackground() {
        guard !items.isEmpty else { return }
        isAnalyzing = true
        analysisProgress = 0

        let snapshotItems = self.items
        let cacheSnapshot = analysisCache.snapshot()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var analyzedItems = snapshotItems
            let analysisService = ImageAnalysisService.shared
            let total = analyzedItems.count
            var featurePrints: [VNFeaturePrintObservation?] = Array(repeating: nil, count: total)
            var pHashes: [UInt64?] = Array(repeating: nil, count: total)

            if !analyzedItems.isEmpty {
                for i in 0..<analyzedItems.count {
                    analyzedItems[i].similarGroupId = nil
                    analyzedItems[i].similarityKind = nil
                }
            }

            var indicesNeedingAnalysis: [Int] = []
            for (index, item) in analyzedItems.enumerated() {
                if let entry = cacheSnapshot[item.id],
                   entry.version == PhotoAnalysisCacheEntry.currentVersion,
                   entry.fileSize == item.fileSize {
                    featurePrints[index] = self.unarchiveFeaturePrint(from: entry.featurePrintData)
                    pHashes[index] = entry.pHash
                    analyzedItems[index].isScreenshot = entry.isScreenshot
                    analyzedItems[index].isDocumentLike = entry.isDocumentLike
                    analyzedItems[index].isTextImage = entry.isTextImage
                    analyzedItems[index].blurScore = entry.blurScore
                    analyzedItems[index].isBlurredOrShaky = entry.isBlurredOrShaky
                    analyzedItems[index].exposureIsBad = entry.exposureIsBad
                    analyzedItems[index].pHash = entry.pHash
                } else {
                    indicesNeedingAnalysis.append(index)
                }
                analyzedItems[index].isLargeFile = item.fileSize > 15 * 1024 * 1024
            }

            var processedCount = total - indicesNeedingAnalysis.count
            if total > 0 {
                DispatchQueue.main.async {
                    self.analysisProgress = Double(processedCount) / Double(total)
                }
            }

            if !indicesNeedingAnalysis.isEmpty {
                let requestOptions = PHImageRequestOptions()
                requestOptions.isSynchronous = true
                requestOptions.deliveryMode = .highQualityFormat
                requestOptions.resizeMode = .exact
                requestOptions.isNetworkAccessAllowed = true
                let targetSize = CGSize(width: 256, height: 256)

                for (offset, index) in indicesNeedingAnalysis.enumerated() {
                    autoreleasepool {
                        var thumbnail: UIImage?
                        let semaphore = DispatchSemaphore(value: 0)
                        let asset = analyzedItems[index].asset
                        self.imageManager.requestImage(
                            for: asset,
                            targetSize: targetSize,
                            contentMode: .aspectFill,
                            options: requestOptions
                        ) { image, _ in
                            thumbnail = image
                            semaphore.signal()
                        }
                        semaphore.wait()

                        if let image = thumbnail {
                            let blurScore = analysisService.computeBlurScore(for: image) ?? 0
                            let exposureBad = analysisService.isExposureBad(for: image)
                            let isBlurred = blurScore < 0.04 || (blurScore < 0.07 && exposureBad)

                            analyzedItems[index].blurScore = blurScore
                            analyzedItems[index].exposureIsBad = exposureBad
                            analyzedItems[index].isBlurredOrShaky = isBlurred

                            let fileSize = analyzedItems[index].fileSize
                            analyzedItems[index].isLargeFile = fileSize > 15 * 1024 * 1024

                            if !analyzedItems[index].isVideo {
                                let feature = analysisService.featurePrint(for: image)
                                featurePrints[index] = feature
                                let hash = analysisService.perceptualHash(for: image)
                                pHashes[index] = hash
                                analyzedItems[index].pHash = hash

                                if #available(iOS 16.0, *), let cgImage = image.cgImage {
                                    let type = AssetTypeDetector.shared.detectAssetTypeSync(asset: asset, image: cgImage)
                                    analyzedItems[index].assetType = type
                                    switch type {
                                    case .screenshot:
                                        analyzedItems[index].isScreenshot = true
                                        analyzedItems[index].isDocumentLike = false
                                        analyzedItems[index].isTextImage = false
                                    case .document:
                                        analyzedItems[index].isDocumentLike = true
                                        analyzedItems[index].isTextImage = false
                                    case .textImage:
                                        analyzedItems[index].isTextImage = true
                                    case .normalPhoto:
                                        break
                                    }
                                } else if !analyzedItems[index].isScreenshot {
                                    let isDoc = analysisService.isDocumentLike(image: image)
                                    analyzedItems[index].isDocumentLike = isDoc
                                }
                            }
                        } else {
                            let fileSize = analyzedItems[index].fileSize
                            analyzedItems[index].isLargeFile = fileSize > 15 * 1024 * 1024
                        }

                        processedCount += 1
                        if offset % 15 == 0 || offset == indicesNeedingAnalysis.count - 1 {
                            let progress = Double(processedCount) / Double(total)
                            DispatchQueue.main.async {
                                self.analysisProgress = progress
                            }
                        }
                    }
                }
            }

            // MARK: - 相似分组
            // 1) 粗分组：按时间窗口 + pHash 预筛选候选集合
            let hasFeaturePrint = featurePrints.contains { $0 != nil }
            if hasFeaturePrint {
                // 按拍摄时间排序索引
                let indices = Array(0..<total).sorted { lhs, rhs in
                    let d1 = analyzedItems[lhs].creationDate ?? .distantPast
                    let d2 = analyzedItems[rhs].creationDate ?? .distantPast
                    return d1 < d2
                }

                // 时间窗口（秒），用于粗分组连拍
                let timeWindow: TimeInterval = 3.0
                var coarseBuckets: [[Int]] = []
                var currentBucket: [Int] = []
                var bucketStartDate: Date?

                for idx in indices {
                    guard let date = analyzedItems[idx].creationDate else { continue }
                    if currentBucket.isEmpty {
                        currentBucket = [idx]
                        bucketStartDate = date
                    } else if let start = bucketStartDate,
                              date.timeIntervalSince(start) <= timeWindow {
                        currentBucket.append(idx)
                    } else {
                        if currentBucket.count > 1 {
                            coarseBuckets.append(currentBucket)
                        }
                        currentBucket = [idx]
                        bucketStartDate = date
                    }
                }
                if currentBucket.count > 1 {
                    coarseBuckets.append(currentBucket)
                }

                // 在每个时间桶内，用 pHash 做进一步粗筛（汉明距离 < 10）
                var candidateGroups: [[Int]] = []
                let pHashThreshold = 10

                for bucket in coarseBuckets {
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
                            candidateGroups.append(group)
                        }
                    }
                }

                // 2) 精分组：在候选集合内用 Vision FeaturePrint 区分「重复」和「轻微差异」
                var globalGroupId = 0
                var assigned = Array(repeating: false, count: total)
                let duplicateThreshold: Float = 10.0
                let similarThreshold: Float = 25.0

                func assignGroup(indices: [Int], kind: SimilarityGroupKind) {
                    guard indices.count > 1 else { return }
                    globalGroupId += 1
                    for idx in indices {
                        analyzedItems[idx].similarGroupId = globalGroupId
                        analyzedItems[idx].similarityKind = kind
                        assigned[idx] = true
                    }
                }

                func clusterWithin(_ indices: [Int]) {
                    let local = indices.filter { featurePrints[$0] != nil }
                    guard !local.isEmpty else { return }

                    // 2.1 先聚类“重复”（距离 < duplicateThreshold）
                    for i in 0..<local.count {
                        let idxI = local[i]
                        if assigned[idxI] { continue }
                        guard let fp1 = featurePrints[idxI] else { continue }

                        var cluster: [Int] = [idxI]
                        for j in (i + 1)..<local.count {
                            let idxJ = local[j]
                            if assigned[idxJ] { continue }
                            guard let fp2 = featurePrints[idxJ] else { continue }
                            if let distance = analysisService.distance(between: fp1, and: fp2),
                               distance < duplicateThreshold {
                                cluster.append(idxJ)
                            }
                        }

                        if cluster.count > 1 {
                            assignGroup(indices: cluster, kind: .duplicate)
                        }
                    }

                    // 2.2 再聚类“轻微差异”（duplicateThreshold...similarThreshold）
                    for i in 0..<local.count {
                        let idxI = local[i]
                        if assigned[idxI] { continue }
                        guard let fp1 = featurePrints[idxI] else { continue }

                        var cluster: [Int] = [idxI]
                        for j in (i + 1)..<local.count {
                            let idxJ = local[j]
                            if assigned[idxJ] { continue }
                            guard let fp2 = featurePrints[idxJ] else { continue }
                            if let distance = analysisService.distance(between: fp1, and: fp2),
                               distance < similarThreshold {
                                cluster.append(idxJ)
                            }
                        }

                        if cluster.count > 1 {
                            assignGroup(indices: cluster, kind: .similar)
                        }
                    }
                }

                for group in candidateGroups {
                    clusterWithin(group)
                }
            } else {
                // Vision 特征全挂了：使用 (宽×高+文件大小) 粗略判定完全一样的照片
                var groupsByKey: [String: [Int]] = [:]
                for (index, item) in analyzedItems.enumerated() {
                    guard !item.isVideo else { continue }
                    let key = "\(Int(item.pixelSize.width))x\(Int(item.pixelSize.height))_\(item.fileSize)"
                    groupsByKey[key, default: []].append(index)
                }

                var groupId = 0
                for (_, indices) in groupsByKey {
                    guard indices.count > 1 else { continue }
                    groupId += 1
                    for idx in indices {
                        analyzedItems[idx].similarGroupId = groupId
                        analyzedItems[idx].similarityKind = .duplicate
                    }
                }
            }

            let cacheEntries = self.buildCacheEntries(from: analyzedItems, featurePrints: featurePrints, pHashes: pHashes)
            self.analysisCache.update(entries: cacheEntries)

            DispatchQueue.main.async {
                let latestItems = self.items
                var deletionMap: [String: Bool] = [:]
                for item in latestItems {
                    deletionMap[item.id] = item.markedForDeletion
                }
                for i in 0..<analyzedItems.count {
                    if let keepFlag = deletionMap[analyzedItems[i].id] {
                        analyzedItems[i].markedForDeletion = keepFlag
                    }
                }

                self.items = analyzedItems
                self.isAnalyzing = false
                self.refreshSession()
            }
        }
    }

    // MARK: - User Actions

    func moveToNext() {
        guard !sessionItems.isEmpty else {
            updateMonthProgressIfNeeded(newValue: 0)
            return
        }

        if currentIndex < sessionItems.count - 1 {
            currentIndex += 1
        } else {
            currentIndex = sessionItems.count
        }

        updateMonthProgressIfNeeded(newValue: currentIndex)
    }

    func markCurrentForDeletion() {
        guard let currentItem = currentItem else { return }
        if let index = items.firstIndex(where: { $0.id == currentItem.id }) {
            items[index].markedForDeletion = true
            persistSelectionState(for: items[index])
        }
        moveToNext()
    }

    func keepCurrent() {
        if let currentItem = currentItem {
            recordSkip(for: currentItem)
        }
        moveToNext()
    }
    
    func skipCurrent() {
        if let currentItem = currentItem {
            recordSkip(for: currentItem)
        }
        moveToNext()
    }
    
    func toggleDeletion(for item: PhotoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion.toggle()
            persistSelectionState(for: items[index])
            refreshSession() // Refresh session to exclude已删除
        }
    }

    func setDeletion(_ item: PhotoItem, to flag: Bool) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion = flag
            persistSelectionState(for: items[index])
            refreshSession()
        }
    }

    func removeFromPending(_ item: PhotoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion = false
            persistSelectionState(for: items[index])
            refreshSession()
        }
    }
    
    func clearPendingDeletionCache() {
        var updated = false
        for index in items.indices {
            if items[index].markedForDeletion {
                items[index].markedForDeletion = false
                persistSelectionState(for: items[index])
                updated = true
            }
        }
        if updated {
            refreshSession()
        }
    }
    
    func resetCleanupProgress() {
        progressStore.resetAll()
        activeMonthContext = nil
        currentIndex = 0
        rebuildMonthStatuses(with: items)
        refreshSession()
    }
    
    func photoItem(for asset: PHAsset, estimatedSize: Int) -> PhotoItem {
        if let existing = items.first(where: { $0.id == asset.localIdentifier }) {
            return existing
        }
        
        return PhotoItem(
            id: asset.localIdentifier,
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
    }

    private func revalidateSimilarGroups() {
        var groupCounts = [Int: Int]()
        let similarItems = items.filter { $0.similarGroupId != nil }
        for item in similarItems {
            if let groupId = item.similarGroupId {
                groupCounts[groupId, default: 0] += 1
            }
        }
        
        let orphanedGroupIds = groupCounts.filter { $1 < 2 }.map { $0.key }
        guard !orphanedGroupIds.isEmpty else { return }
        let orphanedSet = Set(orphanedGroupIds)
        
        for i in 0..<items.count {
            if let groupId = items[i].similarGroupId, orphanedSet.contains(groupId) {
                items[i].similarGroupId = nil
                items[i].similarityKind = nil
            }
        }
    }

    func performDeletion(completion: @escaping (Bool, Error?) -> Void) {
        let toDeleteItems = items.filter { $0.markedForDeletion }
        guard !toDeleteItems.isEmpty else {
            completion(true, nil)
            return
        }

        let toDeleteAssets = toDeleteItems.map { $0.asset }

        // 记录待删除文件总大小与数量
        self.lastFreedSpace = toDeleteItems.reduce(0) { $0 + $1.fileSize }
        self.lastDeletedItemsCount = toDeleteItems.count

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(toDeleteAssets as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.clearStoredRecords(for: toDeleteItems)
                    let toDeleteIds = Set(toDeleteAssets.map { $0.localIdentifier })
                    self.analysisCache.removeEntries(for: Array(toDeleteIds))
                    self.items.removeAll { toDeleteIds.contains($0.id) }
                    self.revalidateSimilarGroups()
                    self.refreshSession()
                    // 触发成功页面
                    self.presentSuccessSummary()
                }
                completion(success, error)
            }
        }
    }

    private func presentSuccessSummary() {
        if isShowingCleaner {
            isShowingSuccessSummary = true
        } else {
            activeDetail = .success
        }
    }
    
    private func refreshDeviceStorageUsage() {
        DispatchQueue.global(qos: .utility).async {
            let usage = DeviceStorageUsage.current()
            DispatchQueue.main.async {
                self.deviceStorageUsage = usage
            }
        }
    }

    // MARK: - Month Status Tracking

    func markMonth(year: Int, month: Int, asCleaned cleaned: Bool) {
        let key = monthKey(year: year, month: month)
        guard var status = monthStatuses[key] else { return }
        status.userCleaned = cleaned
        monthStatuses[key] = status
        progressStore.setMonthCleaned(year: year, month: month, cleaned: cleaned)
    }

    func computeMonthStatus(photos: [PhotoItem]) -> MonthStatus {
        guard !photos.isEmpty else {
            return MonthStatus(totalPhotos: 0, predictedPendingCount: 0, userCleaned: false)
        }

        let predicted = photos.reduce(into: 0) { partialResult, item in
            if shouldFlagForCleanup(item) {
                partialResult += 1
            }
        }

        return MonthStatus(
            totalPhotos: photos.count,
            predictedPendingCount: predicted,
            userCleaned: false
        )
    }

    private func rebuildMonthStatuses(with items: [PhotoItem]) {
        let grouped = Dictionary(grouping: items) { (item: PhotoItem) -> String in
            let date = item.creationDate ?? Date()
            let comps = Calendar.current.dateComponents([.year, .month], from: date)
            return monthKey(year: comps.year ?? 0, month: comps.month ?? 0)
        }

        var updated: [String: MonthStatus] = [:]
        for (key, photos) in grouped {
            var status = computeMonthStatus(photos: photos)
            if
                let comps = components(fromMonthKey: key),
                let persisted = progressStore.progress(year: comps.year, month: comps.month)
            {
                status.userCleaned = persisted.isMarkedCleaned
            } else if let existing = monthStatuses[key] {
                status.userCleaned = existing.userCleaned
            }
            updated[key] = status
        }

        monthStatuses = updated
    }

    private func rebuildMonthSession(year: Int, month: Int) {
        sessionItems = monthItems(year: year, month: month)
        currentFilter = .all
        let storedProgress = progressStore.progress(year: year, month: month)?.processedCount ?? 0
        currentIndex = min(storedProgress, sessionItems.count)
    }

    private func restoreSelectionStates(in items: inout [PhotoItem]) {
        for index in items.indices {
            guard
                let comps = monthComponents(for: items[index]),
                let progress = progressStore.progress(year: comps.year, month: comps.month)
            else { continue }
            if progress.selectedPhotoIds.contains(items[index].id) {
                items[index].markedForDeletion = true
            }
        }
    }
    
    private func applyCachedAnalysis(to items: inout [PhotoItem]) {
        let cacheEntries = analysisCache.snapshot()
        for index in items.indices {
            guard let entry = cacheEntries[items[index].id],
                  entry.version == PhotoAnalysisCacheEntry.currentVersion,
                  entry.fileSize == items[index].fileSize else {
                continue
            }
            items[index].isScreenshot = entry.isScreenshot
            items[index].isDocumentLike = entry.isDocumentLike
            items[index].isTextImage = entry.isTextImage
            items[index].blurScore = entry.blurScore
            items[index].isBlurredOrShaky = entry.isBlurredOrShaky
            items[index].exposureIsBad = entry.exposureIsBad
            items[index].pHash = entry.pHash
            items[index].similarGroupId = entry.similarityGroupId
            if let kindRaw = entry.similarityKind {
                items[index].similarityKind = SimilarityGroupKind(rawValue: kindRaw)
            } else {
                items[index].similarityKind = nil
            }
            items[index].isLargeFile = items[index].fileSize > 15 * 1024 * 1024
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

    private func persistSelectionState(for item: PhotoItem) {
        guard let comps = monthComponents(for: item) else { return }
        progressStore.setPhoto(item.id, year: comps.year, month: comps.month, markedForDeletion: item.markedForDeletion)
    }

    private func recordSkip(for item: PhotoItem) {
        guard let comps = monthComponents(for: item) else { return }
        progressStore.recordSkip(item.id, year: comps.year, month: comps.month)
    }

    private func clearStoredRecords(for items: [PhotoItem]) {
        for item in items {
            guard let comps = monthComponents(for: item) else { continue }
            progressStore.removePhotoRecords(item.id, year: comps.year, month: comps.month)
        }
    }

    private func updateMonthProgressIfNeeded(newValue: Int) {
        guard let context = activeMonthContext else { return }
        progressStore.updateProcessedCount(year: context.year, month: context.month, to: newValue)
    }

    private func monthComponents(for item: PhotoItem) -> (year: Int, month: Int)? {
        guard let date = item.creationDate else { return nil }
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        return (year, month)
    }

    private func components(fromMonthKey key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return nil
        }
        return (year, month)
    }
    
    private func monthItems(year: Int, month: Int) -> [PhotoItem] {
        let calendar = Calendar.current
        let filtered = items.filter { item in
            guard !item.markedForDeletion, let date = item.creationDate else { return false }
            let comps = calendar.dateComponents([.year, .month], from: date)
            return comps.year == year && comps.month == month
        }
        return filtered.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    private func shouldFlagForCleanup(_ item: PhotoItem) -> Bool {
        if item.similarGroupId != nil { return true }
        if item.isScreenshot || item.isDocumentLike || item.isTextImage { return true }
        if item.isBlurredOrShaky { return true }
        if item.isLargeFile && !item.isVideo { return true }
        return false
    }

    private func monthKey(year: Int, month: Int) -> String {
        "\(year)-\(month)"
    }
    
    func assetResourceSize(for asset: PHAsset) -> Int {
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
    
    func fetchAssets(in sizeRange: SizeRange, limit: Int? = nil) -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = []
        let result = PHAsset.fetchAssets(with: fetchOptions)
        var sized: [(PHAsset, Int)] = []
        result.enumerateObjects { asset, _, _ in
            let size = self.assetResourceSize(for: asset)
            if sizeRange.contains(size) {
                sized.append((asset, size))
            }
        }
        let sorted = sized.sorted { $0.1 > $1.1 }
        if let limit, limit > 0 {
            return Array(sorted.prefix(limit)).map { $0.0 }
        }
        return sorted.map { $0.0 }
    }
}

struct SizeRange: Hashable {
    let minBytes: Int
    let maxBytes: Int?
    
    func contains(_ size: Int) -> Bool {
        guard size >= minBytes else { return false }
        if let maxBytes {
            return size <= maxBytes
        }
        return true
    }
    
    static let medium = SizeRange(minBytes: 10 * 1_024 * 1_024, maxBytes: 20 * 1_024 * 1_024)
    static let large = SizeRange(minBytes: 20 * 1_024 * 1_024, maxBytes: 50 * 1_024 * 1_024)
    static let ultra = SizeRange(minBytes: 50 * 1_024 * 1_024, maxBytes: nil)
}

struct DeviceStorageUsage {
    let totalBytes: Int64
    let freeBytes: Int64
    
    var usedBytes: Int64 {
        max(totalBytes - freeBytes, 0)
    }
    
    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
    
    var hasValidData: Bool { totalBytes > 0 }
    
    var formattedPercentageText: String? {
        guard hasValidData else { return nil }
        let percent = max(0, min(usagePercentage * 100, 100))
        return String(format: "%.0f%%", percent)
    }
    
    var formattedUsageDetailText: String? {
        guard hasValidData else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let used = formatter.string(fromByteCount: usedBytes)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(used) / \(total)"
    }
    
    static let empty = DeviceStorageUsage(totalBytes: 0, freeBytes: 0)
    
    static func current() -> DeviceStorageUsage {
        let path = NSHomeDirectory()
        guard
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
            let total = attributes[.systemSize] as? NSNumber,
            let free = attributes[.systemFreeSize] as? NSNumber
        else {
            return .empty
        }
        
        return DeviceStorageUsage(
            totalBytes: total.int64Value,
            freeBytes: free.int64Value
        )
    }
}
