import SwiftUI
import Combine
import Photos
import Vision

final class PhotoCleanupViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    // MARK: - Properties
    
    // Status
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var isLoading: Bool = false
    @Published var selectedTheme: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "app_theme") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "app_theme")
        }
    }

    // Data
    @Published var items: [PhotoItem] = []
    @Published var monthAssetTotals: [String: Int] = [:]
    @Published var sessionItems: [PhotoItem] = []
    @Published var lastFreedSpace: Int = 0
    @Published var lastDeletedItemsCount: Int = 0
    @Published var deviceStorageUsage: DeviceStorageUsage = .empty
    @Published private(set) var timeMachineSnapshots: [String: TimeMachineMonthProgress] = [:]
    @Published var albumFilters: [AlbumFilter] = [.all]
    @Published var selectedAlbumFilter: AlbumFilter = .all
    
    // Navigation & Session State
    @Published var currentTab: AppView = .dashboard
    @Published var isShowingCleaner: Bool = false
    @Published var activeDetail: DashboardDetail?
    @Published var isShowingSuccessSummary: Bool = false
    @Published var settingsNavigationPath = NavigationPath()
    
    @Published var currentFilter: CleanupFilterMode = .all
    @Published var currentIndex: Int = 0 {
        didSet {
            captureSmartCleanupAnchor()
            elevateAnalysisPriorityForVisibleItems()
        }
    }
    private var activeMonthContext: (year: Int, month: Int)?

    // Services
    let imageManager = PHCachingImageManager()
    private let userStateRepo: PhotoUserStateRepository
    @Published private(set) var smartCleanupProgress: SmartCleanupProgress?
    @Published private(set) var skippedPhotoRecords: [SkippedPhotoRecord] = []
    private let analysisCache: PhotoAnalysisRepository
    private let queryService = PhotoQueryService()
    private var assetsFetchResult: PHFetchResult<PHAsset>?
    private var cancellable: AnyCancellable?
    private let zeroLatencyImageCache = ImageCache()
    private lazy var pagingLoader: PhotoLoader = {
        let loader = PhotoLoader(imageCache: zeroLatencyImageCache)
        loader.delegate = self
        return loader
    }()
    private var loadedAssetIdentifiers: Set<String> = []
    private var hasStartedPagingLoader = false
    private var hasTriggeredBackgroundAnalysis = false
    private var hasInitializedSession = false
    private var sessionItemIds: Set<String> = []
    private var selectedAlbumAssetIds: Set<String>?
    private var hasLoadedAlbumFilters = false
    private var monthPrefetchingKeys: Set<String> = []
    private var hasScheduledInitialAssetLoad = false

    // Data controller（加载/分析/持久化）
    private let dataController: PhotoDataController
    private var lastSnapshotItemIds: Set<String> = []

    // MARK: - Computed Properties
    
    // Session Items
    var currentItem: PhotoItem? { sessionItems[safe: currentIndex] }
    var nextItem: PhotoItem? { sessionItems[safe: currentIndex + 1] }
    var thirdItem: PhotoItem? { sessionItems[safe: currentIndex + 2] }
    
    struct SmartCleanupResumeInfo {
        let lastCategory: CleanupFilterMode
        let anchorPhoto: PhotoItem?
        let pendingDeletionCount: Int
    }
    
    var smartCleanupResumeInfo: SmartCleanupResumeInfo? {
        guard
            let progress = smartCleanupProgress,
            let anchorId = progress.lastPhotoId,
            let anchorPhoto = items.first(where: { $0.id == anchorId })
        else {
            return nil
        }

        return SmartCleanupResumeInfo(
            lastCategory: progress.lastCategory,
            anchorPhoto: anchorPhoto,
            pendingDeletionCount: pendingDeletionItems.count
        )
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
        timeMachineProgressStore: TimeMachineProgressStore = TimeMachineProgressStore(),
        smartCleanupProgressStore: SmartCleanupProgressStore = SmartCleanupProgressStore(),
        skippedPhotoStore: SkippedPhotoStore = SkippedPhotoStore(),
        analysisCache: PhotoAnalysisCacheStore = PhotoAnalysisCacheStore()
    ) {
        // 使用全局数据容器，保证与 ZeroLatency 共享同一数据层
        let container = PhotoDataContainer.shared
        self.analysisCache = container.analysisRepository
        self.userStateRepo = container.userStateRepository
        self.dataController = container.dataController
        super.init()

        // 绑定数据控制器快照
        let previousSnapshotHandler = dataController.onSnapshotChange
        dataController.onSnapshotChange = { [weak self] snapshot in
            previousSnapshotHandler?(snapshot)
            self?.applySnapshot(snapshot)
        }
        applySnapshot(dataController.currentSnapshot())

        PHPhotoLibrary.shared().register(self)
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            scheduleInitialAssetLoad()
        }
        
        cancellable = NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.updateAuthorizationStatus()
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
                self.scheduleInitialAssetLoad()
            }
        }
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let fetchResult = assetsFetchResult,
              let details = changeInstance.changeDetails(for: fetchResult) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // 如果不是增量变更（或当前尚未加载任何 items），回退到旧逻辑以保证正确性。
            guard details.hasIncrementalChanges, !self.items.isEmpty else {
                self.resetPagingState()
                self.pagingLoader.reloadLibrary()
                return
            }

            // 1) 让分页加载器增量更新 fetchResult / 预热窗口等。
            self.pagingLoader.applyChangeDetails(details)

            // 2) 由 dataController 统一应用变更并调度分析。
            self.dataController.applyLibraryChange(details)
        }
    }
    
    // MARK: - Navigation
    
    func showCleaner(filter: CleanupFilterMode) {
        activeMonthContext = nil
        isShowingCleaner = true
        updateSessionItems(for: filter)
    }

    func resumeSmartCleanup() {
        let category = smartCleanupProgress?.lastCategory ?? .all
        showCleaner(filter: category)
        if let anchorId = smartCleanupProgress?.lastPhotoId,
           let index = sessionItems.firstIndex(where: { $0.id == anchorId }) {
            currentIndex = index
        }
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
        let filtered = filteredItems(for: filter, from: items)
        sessionItems = filtered
        sessionItemIds = Set(filtered.map(\.id))
        currentIndex = 0
        elevateAnalysisPriority(for: filtered)
    }

    func refreshSession() {
        if let context = activeMonthContext {
            rebuildMonthSession(year: context.year, month: context.month)
        } else {
            let filtered = filteredItems(for: currentFilter, from: items)
            sessionItems = filtered
            sessionItemIds = Set(filtered.map(\.id))
            currentIndex = min(currentIndex, max(sessionItems.count - 1, 0))
        }
    }

    func selectAlbumFilter(_ filter: AlbumFilter) {
        guard selectedAlbumFilter != filter else { return }
        selectedAlbumFilter = filter
        if let collection = filter.collection {
            selectedAlbumAssetIds = nil
            hasInitializedSession = false
            sessionItems = []
            sessionItemIds.removeAll()
            currentIndex = 0
            Task.detached { [weak self] in
                guard let self else { return }
                let ids = await self.fetchAssetIdentifiers(in: collection)
                await MainActor.run {
                    self.selectedAlbumAssetIds = ids
                    self.updateSessionItems(for: self.currentFilter)
                }
            }
        } else {
            selectedAlbumAssetIds = nil
            updateSessionItems(for: currentFilter)
        }
    }

    private func resetSessionForAlbumChange() {
        hasInitializedSession = false
        sessionItems = []
        sessionItemIds.removeAll()
        currentIndex = 0
        updateSessionItems(for: currentFilter)
        objectWillChange.send()
    }

    // MARK: - Data Loading & Analysis

    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorizationStatus = newStatus
                if newStatus == .authorized || newStatus == .limited {
                    self.scheduleInitialAssetLoad()
                }
            }
        }
    }

    func loadAssets() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performInitialAssetLoad()
        }
    }

    private func scheduleInitialAssetLoad() {
        guard !hasScheduledInitialAssetLoad else { return }
        hasScheduledInitialAssetLoad = true
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.performInitialAssetLoad()
        }
    }

    private func performInitialAssetLoad() {
        loadAlbumFiltersIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
            self.isLoading = true
            self.startPagingLoader()
        }
    }

    func ensureAssetsPrepared() {
        scheduleInitialAssetLoad()
    }

    private func assets(in fetchResult: PHFetchResult<PHAsset>, year: Int, month: Int) -> [PHAsset] {
        var matched: [PHAsset] = []
        let calendar = Calendar.current
        fetchResult.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate ?? asset.modificationDate else { return }
            let comps = calendar.dateComponents([.year, .month], from: date)
            if comps.year == year && comps.month == month {
                matched.append(asset)
            }
        }
        return matched
    }

    private func startPagingLoader() {
        if hasStartedPagingLoader {
            resetPagingState()
            pagingLoader.reloadLibrary()
        } else {
            hasStartedPagingLoader = true
            pagingLoader.start()
        }
    }

    private func loadAlbumFiltersIfNeeded() {
        guard !hasLoadedAlbumFilters else { return }
        hasLoadedAlbumFilters = true
        Task.detached { [weak self] in
            guard let self else { return }
            var filters: [AlbumFilter] = [.all]
            var seen = Set<String>()
            seen.insert(AlbumFilter.all.id)

            let userCollections = PHCollectionList.fetchTopLevelUserCollections(with: nil)
            userCollections.enumerateObjects { collection, _, _ in
                guard let assetCollection = collection as? PHAssetCollection else { return }
                let identifier = assetCollection.localIdentifier
                guard !seen.contains(identifier) else { return }
                seen.insert(identifier)
                let name = collection.localizedTitle ?? "未命名"
                filters.append(AlbumFilter(id: identifier, name: name, collection: assetCollection))
            }

            let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .albumRegular, options: nil)
            smartAlbums.enumerateObjects { collection, _, _ in
                let identifier = collection.localIdentifier
                guard !seen.contains(identifier) else { return }
                seen.insert(identifier)
                let name = collection.localizedTitle ?? "智能相册"
                filters.append(AlbumFilter(id: identifier, name: name, collection: collection))
            }

            await MainActor.run {
                self.albumFilters = filters
                if !filters.contains(where: { $0.id == self.selectedAlbumFilter.id }) {
                    self.selectedAlbumFilter = filters.first ?? .all
                }
            }
        }
    }

    private func fetchAssetIdentifiers(in collection: PHAssetCollection) async -> Set<String> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var identifiers = Set<String>()
                let result = PHAsset.fetchAssets(in: collection, options: nil)
                result.enumerateObjects { asset, _, _ in
                    identifiers.insert(asset.localIdentifier)
                }
                continuation.resume(returning: identifiers)
            }
        }
    }

    private func resetPagingState() {
        loadedAssetIdentifiers.removeAll()
        hasTriggeredBackgroundAnalysis = false
        hasInitializedSession = false
        sessionItemIds.removeAll()
        items = []
        sessionItems = []
        currentIndex = 0
        currentFilter = .all
        lastSnapshotItemIds.removeAll()
        dataController.resetPagingState()
    }

    private func applySnapshot(_ snapshot: PhotoDataController.Snapshot) {
        let previousIds = lastSnapshotItemIds
        let newIds = Set(snapshot.items.map(\.id))
        let incoming = snapshot.items.filter { !previousIds.contains($0.id) }
        lastSnapshotItemIds = newIds

        items = snapshot.items
        monthAssetTotals = snapshot.monthAssetTotals
        timeMachineSnapshots = snapshot.timeMachineSnapshots
        skippedPhotoRecords = snapshot.skippedPhotoRecords
        smartCleanupProgress = snapshot.smartCleanupProgress

        if isLoading && !items.isEmpty {
            isLoading = false
        }

        if !hasInitializedSession {
            hasInitializedSession = true
            updateSessionItems(for: currentFilter)
        } else if !isShowingCleaner {
            refreshSession()
        } else if activeMonthContext == nil {
            appendIncomingToSession(newItems: incoming)
        }
    }

    private func ingestAssets(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let cacheEntries = analysisCache.snapshot()
        var incoming: [PhotoItem] = []

        for asset in assets {
            let id = asset.localIdentifier
            if loadedAssetIdentifiers.contains(id) { continue }
            loadedAssetIdentifiers.insert(id)
            let estimatedSize = assetResourceSize(for: asset)
            var item = photoItem(for: asset, estimatedSize: estimatedSize)
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
        if isLoading {
            isLoading = false
        }
        if !hasInitializedSession {
            hasInitializedSession = true
            updateSessionItems(for: currentFilter)
        } else if !isShowingCleaner {
            refreshSession()
        } else if activeMonthContext == nil {
            appendIncomingToSession(newItems: incoming)
        }
        scheduleBackgroundAnalysisIfNeeded()
    }

    private func appendIncomingToSession(newItems: [PhotoItem]) {
        guard !newItems.isEmpty else { return }
        let filtered = filteredItems(for: currentFilter, from: newItems)
            .filter { !sessionItemIds.contains($0.id) }
        guard !filtered.isEmpty else { return }
        sessionItems.append(contentsOf: filtered)
        filtered.forEach { sessionItemIds.insert($0.id) }
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

    private func scheduleBackgroundAnalysisIfNeeded() {
        // 分析调度已下沉到 dataController；此处保留以兼容旧调用路径。
    }

    private func elevateAnalysisPriority(for candidates: [PhotoItem]) {
        dataController.elevateAnalysisPriority(for: candidates)
    }

    private func elevateAnalysisPriorityForVisibleItems() {
        let visibles = [currentItem, nextItem, thirdItem].compactMap { $0 }
        dataController.elevateAnalysisPriority(for: visibles)
    }

    private func processSimilarGroups(analyzedItems: inout [PhotoItem], featurePrints: [VNFeaturePrintObservation?], pHashes: [UInt64?]) {
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
// MARK: - User Actions

    func moveToNext() {
        guard !sessionItems.isEmpty else {
            return
        }

        if currentIndex < sessionItems.count - 1 {
            currentIndex += 1
        } else {
            currentIndex = sessionItems.count
        }
    }

    private func removeCurrentItemFromSession() {
        guard !sessionItems.isEmpty else {
            return
        }
        let removedIndex = currentIndex
        sessionItemIds.remove(sessionItems[removedIndex].id)
        sessionItems.remove(at: removedIndex)
        if sessionItems.isEmpty {
            currentIndex = 0
        } else if currentIndex >= sessionItems.count {
            currentIndex = max(sessionItems.count - 1, 0)
        }
    }

    func markCurrentForDeletion() {
        guard let currentItem = currentItem else { return }
        dataController.setMarkedForDeletion(photoId: currentItem.id, flag: true)
        var updatedItem = currentItem
        updatedItem.markedForDeletion = true
        persistSelectionState(for: updatedItem)
        syncSmartCleanupPendingFlag()
        moveToNext()
    }

    func keepCurrent() {
        guard let currentItem = currentItem else { return }
        recordConfirmation(for: currentItem)
        removeCurrentItemFromSession()
    }
    
    func skipCurrent() {
        guard let currentItem = currentItem else { return }
        logSkippedPhoto(currentItem, source: currentSkippedSource())
        removeCurrentItemFromSession()
    }
    
    func toggleDeletion(for item: PhotoItem) {
        let currentFlag = items.first(where: { $0.id == item.id })?.markedForDeletion ?? item.markedForDeletion
        let newFlag = !currentFlag
        dataController.setMarkedForDeletion(photoId: item.id, flag: newFlag)
        var updatedItem = item
        updatedItem.markedForDeletion = newFlag
        persistSelectionState(for: updatedItem)
        syncSmartCleanupPendingFlag()
        refreshSession() // Refresh session to exclude已删除
    }

    func setDeletion(_ item: PhotoItem, to flag: Bool) {
        dataController.setMarkedForDeletion(photoId: item.id, flag: flag)
        var updatedItem = item
        updatedItem.markedForDeletion = flag
        persistSelectionState(for: updatedItem)
        syncSmartCleanupPendingFlag()
        refreshSession()
    }

    func removeFromPending(_ item: PhotoItem) {
        dataController.setMarkedForDeletion(photoId: item.id, flag: false)
        var updatedItem = item
        updatedItem.markedForDeletion = false
        persistSelectionState(for: updatedItem)
        syncSmartCleanupPendingFlag()
        refreshSession()
    }
    
    func clearPendingDeletionCache() {
        let toClear = items.filter { $0.markedForDeletion }
        guard !toClear.isEmpty else { return }
        for item in toClear {
            var updatedItem = item
            updatedItem.markedForDeletion = false
            persistSelectionState(for: updatedItem)
        }
        dataController.clearMarkedForDeletion(photoIds: toClear.map(\.id))
        syncSmartCleanupPendingFlag()
        refreshSession()
    }
    
    func resetCleanupProgress() {
        dataController.resetAllTimeMachine()
        storeSmartCleanupProgress(nil)
        activeMonthContext = nil
        currentIndex = 0
        refreshSession()
    }
    
    func resetSmartCleanupProgressOnly() {
        storeSmartCleanupProgress(nil)
    }
    
    func resetTimeMachineProgress() {
        dataController.resetAllTimeMachine()
        if let context = activeMonthContext {
            rebuildMonthSession(year: context.year, month: context.month)
        } else {
            refreshSession()
        }
    }

    func timeMachineProgress(year: Int, month: Int) -> TimeMachineMonthProgress? {
        timeMachineSnapshots[monthKey(year: year, month: month)]
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
                    self.dataController.removeAnalysisEntries(ids: Array(toDeleteIds))
                    self.dataController.removeItems(ids: toDeleteIds)
                    self.refreshSession()
                    self.syncSmartCleanupPendingFlag()
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

    private func rebuildMonthSession(year: Int, month: Int) {
        sessionItems = monthItems(year: year, month: month)
        currentFilter = .all
        currentIndex = 0
        sessionItemIds = Set(sessionItems.map(\.id))
        elevateAnalysisPriority(for: sessionItems)
    }

    private func restoreSelectionStates(in items: inout [PhotoItem]) {
        for index in items.indices {
            guard
                let comps = monthComponents(for: items[index])
            else { continue }
            let key = monthKey(year: comps.year, month: comps.month)
            if let progress = timeMachineSnapshots[key],
               progress.selectedPhotoIds.contains(items[index].id) {
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
    
    private func storeSmartCleanupProgress(_ progress: SmartCleanupProgress?) {
        dataController.updateSmartCleanupProgress(progress)
    }

    private func captureSmartCleanupAnchor() {
        guard activeMonthContext == nil, isShowingCleaner, let anchorId = currentItem?.id else { return }
        var progress = smartCleanupProgress ?? SmartCleanupProgress(lastCategoryRawValue: currentFilter.rawValue)
        progress.lastCategoryRawValue = currentFilter.rawValue
        progress.lastPhotoId = anchorId
        progress.hasPendingItems = !pendingDeletionItems.isEmpty
        progress.lastUpdatedAt = Date()
        storeSmartCleanupProgress(progress)
    }

    private func syncSmartCleanupPendingFlag() {
        guard var progress = smartCleanupProgress else { return }
        progress.hasPendingItems = !pendingDeletionItems.isEmpty
        progress.lastUpdatedAt = Date()
        if !progress.hasPendingItems && progress.lastPhotoId == nil {
            storeSmartCleanupProgress(nil)
        } else {
            storeSmartCleanupProgress(progress)
        }
    }

    private func refreshSkippedPhotoRecords() {
        dataController.refreshSkippedRecords()
    }

    private func refreshTimeMachineSnapshots() {
        dataController.refreshTimeMachineSnapshots()
    }

    func logSkippedPhoto(_ item: PhotoItem, source: SkippedPhotoSource) {
        dataController.recordSkipped(photoId: item.id, source: source)
    }

    func markSkippedRecordsProcessed(ids: [String]) {
        guard !ids.isEmpty else { return }
        dataController.markSkippedProcessed(ids: ids)
    }

    func deleteSkippedRecords(ids: [String]) {
        guard !ids.isEmpty else { return }
        dataController.removeSkipped(ids: ids)
    }

    func clearSkippedRecords() {
        dataController.clearSkipped()
    }
    
    func confirmDeletionForSkipped(ids: [String]) {
        guard !ids.isEmpty else { return }
        var updated = false
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            dataController.setMarkedForDeletion(photoId: id, flag: true)
            var updatedItem = item
            updatedItem.markedForDeletion = true
            persistSelectionState(for: updatedItem)
            updated = true
        }
        if updated {
            syncSmartCleanupPendingFlag()
            refreshSession()
        }
        dataController.removeSkipped(ids: ids)
    }
    
    func reinstateSkippedPhotos(ids: [String]) {
        guard !ids.isEmpty else { return }
        dataController.removeSkipped(ids: ids)
    }
    
    func acknowledgeSkippedPhotos(ids: [String]) {
        guard !ids.isEmpty else { return }
        dataController.removeSkipped(ids: ids)
    }

    private func persistSelectionState(for item: PhotoItem) {
        guard let comps = monthComponents(for: item) else { return }
        dataController.setPhotoSelected(item.id, year: comps.year, month: comps.month, selected: item.markedForDeletion)
    }

    private func recordConfirmation(for item: PhotoItem) {
        guard let comps = monthComponents(for: item) else { return }
        dataController.confirmPhoto(item.id, year: comps.year, month: comps.month)
    }

    private func clearStoredRecords(for items: [PhotoItem]) {
        for item in items {
            guard let comps = monthComponents(for: item) else { continue }
            dataController.removePhotoRecords(item.id, year: comps.year, month: comps.month)
        }
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
        let key = "\(year)-\(month)"
        let sorted = queryService.monthItems(
            year: year,
            month: month,
            from: items,
            isDeferredInTimeMachine: { [weak self] item in
                self?.isPhotoDeferredInTimeMachine(item) ?? false
            }
        )
        #if DEBUG
        let totalInMonth = queryService.monthTotalCount(year: year, month: month, in: items)
        let deferredCount = totalInMonth - sorted.count
        print("[TimeMachineMonthItems] \(year)-\(month): total=\(totalInMonth) visible=\(sorted.count) deferred=\(deferredCount)")
        #endif
        if sorted.isEmpty,
           let total = monthAssetTotals[key], total > 0 {
            prefetchMonthAssetsIfNeeded(year: year, month: month)
        }
        return sorted
    }

    private func filteredItems(for filter: CleanupFilterMode, from collection: [PhotoItem]) -> [PhotoItem] {
        queryService.filteredItems(
            filter: filter,
            from: collection,
            isDeferredInTimeMachine: { [weak self] item in
                self?.isPhotoDeferredInTimeMachine(item) ?? false
            },
            isInSelectedAlbum: { [weak self] item in
                self?.isItemInSelectedAlbum(item) ?? true
            }
        )
    }
    
    private func currentSkippedSource() -> SkippedPhotoSource {
        if activeMonthContext != nil {
            return .timeMachine
        }
        switch currentFilter {
        case .similar: return .similar
        case .blurred: return .blurred
        case .screenshots: return .screenshots
        case .documents: return .documents
        case .large: return .large
        default: return .smart
        }
    }

    private func isItemInSelectedAlbum(_ item: PhotoItem) -> Bool {
        guard selectedAlbumFilter.collection != nil else { return true }
        guard let ids = selectedAlbumAssetIds else {
            // 尚未加载该相册的 asset ID，暂时视为不在相册中，等待加载完成
            return false
        }
        return ids.contains(item.id)
    }

    private func isPhotoDeferredInTimeMachine(_ item: PhotoItem) -> Bool {
        guard let comps = monthComponents(for: item) else { return false }
        let key = monthKey(year: comps.year, month: comps.month)
        if let progress = timeMachineSnapshots[key],
           progress.confirmedPhotoIds.contains(item.id) {
            return true
        }
        return timeMachineSkippedPhotoIds.contains(item.id)
    }

    private var timeMachineSkippedPhotoIds: Set<String> {
        Set(skippedPhotoRecords.filter { $0.source == .timeMachine }.map(\.photoId))
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

struct AlbumFilter: Identifiable, Equatable {
    let id: String
    let name: String
    let collection: PHAssetCollection?

    static let all = AlbumFilter(id: "all", name: "全部相册", collection: nil)

    static func == (lhs: AlbumFilter, rhs: AlbumFilter) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
extension PhotoCleanupViewModel: PhotoLoaderDelegate {
    func photoLoader(_ loader: PhotoLoader, didUpdateFetchResult fetchResult: PHFetchResult<PHAsset>) {
        assetsFetchResult = fetchResult
        dataController.handleFetchResultUpdate(fetchResult)
    }

    func photoLoader(_ loader: PhotoLoader, didLoadAssets assets: [PHAsset]) {
        dataController.handleLoadedAssets(assets)
        for asset in assets where asset.mediaType == .video || asset.mediaSubtypes.contains(.photoLive) {
            preheatVideo(for: asset)
        }
    }

    private func preheatVideo(for asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .mediumQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { _, _, _ in }
    }

    private func rebuildMonthAssetTotals(from fetchResult: PHFetchResult<PHAsset>) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
            DispatchQueue.main.async {
                self.monthAssetTotals = counts
                #if DEBUG
                print("[MonthAssetTotals] totals=\(counts)")
                #endif
            }
        }
    }

    private func prefetchMonthAssetsIfNeeded(year: Int, month: Int) {
        guard let fetchResult = assetsFetchResult else { return }
        let key = "\(year)-\(month)"
        guard !monthPrefetchingKeys.contains(key) else { return }
        monthPrefetchingKeys.insert(key)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let assets = self.assets(in: fetchResult, year: year, month: month)
            let limitedAssets = Array(assets.prefix(400))
            DispatchQueue.main.async {
                self.dataController.handleLoadedAssets(limitedAssets)
                self.monthPrefetchingKeys.remove(key)
            }
        }
    }
}
