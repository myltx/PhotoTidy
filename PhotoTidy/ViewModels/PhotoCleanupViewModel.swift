import SwiftUI
import Combine
import Photos
import Vision

final class PhotoCleanupViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static weak var shared: PhotoCleanupViewModel?
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
    @Published private(set) var metadataSnapshot: MetadataSnapshot = .empty
    @Published private(set) var timeMachineSnapshots: [String: TimeMachineMonthProgress] = [:]
    @Published private(set) var largeImageCache: [String: UIImage] = [:]
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
            updateLargeImageWindowIfNeeded(center: currentIndex)
        }
    }
    private var activeMonthContext: (year: Int, month: Int)?

    // Services
    let imageManager = PHCachingImageManager()
    private let timeMachineProgressStore: TimeMachineProgressStore
    private let smartCleanupProgressStore: SmartCleanupProgressStore
    private let skippedPhotoStore: SkippedPhotoStore
    @Published private(set) var smartCleanupProgress: SmartCleanupProgress?
    @Published private(set) var skippedPhotoRecords: [SkippedPhotoRecord] = []
    private let analysisCache: PhotoAnalysisCacheStore
    private let metadataRepository: MetadataRepository
    private let photoRepository = PhotoRepository()
    private let imagePipeline = ImagePipeline()
    private let largeImagePager = LargeImagePager()
    private let taskPool = TaskPool()
    private let backgroundScheduler = BackgroundJobScheduler()
    private var assetsFetchResult: PHFetchResult<PHAsset>?
    private var cancellables: Set<AnyCancellable> = []
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

    // MARK: - Computed Properties
    
    // Session Items
    var currentItem: PhotoItem? { sessionItems[safe: currentIndex] }
    var nextItem: PhotoItem? { sessionItems[safe: currentIndex + 1] }
    var thirdItem: PhotoItem? { sessionItems[safe: currentIndex + 2] }

    var isZeroLatencyTimeMachineSession: Bool {
        FeatureToggles.useZeroLatencyTimeMachine && activeMonthContext != nil
    }

    func cachedLargeImage(for id: String) -> UIImage? {
        largeImageCache[id]
    }
    
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
    var similarItemsCount: Int {
        if FeatureToggles.enableZeroLatencyPipeline, items.isEmpty {
            return metadataSnapshot.categoryCounters.similar
        }
        return items.filter { $0.similarGroupId != nil }.count
    }
    var blurredItemsCount: Int {
        if FeatureToggles.enableZeroLatencyPipeline, items.isEmpty {
            return metadataSnapshot.categoryCounters.blurred
        }
        return items.filter { $0.isBlurredOrShaky }.count
    }
    var screenshotItemsCount: Int {
        if FeatureToggles.enableZeroLatencyPipeline, items.isEmpty {
            return metadataSnapshot.categoryCounters.screenshot + metadataSnapshot.categoryCounters.document
        }
        return items.filter { $0.isScreenshot || $0.isDocumentLike }.count
    }
    var largeFilesSize: Int {
        if FeatureToggles.enableZeroLatencyPipeline, items.isEmpty {
            return metadataSnapshot.categoryCounters.largeFile * (15 * 1_024 * 1_024)
        }
        return items.filter { $0.isLargeFile }.map { $0.fileSize }.reduce(0, +)
    }

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
        self.analysisCache = analysisCache
        self.metadataRepository = MetadataRepository(analysisCache: analysisCache)
        self.timeMachineProgressStore = timeMachineProgressStore
        self.smartCleanupProgressStore = smartCleanupProgressStore
        self.skippedPhotoStore = skippedPhotoStore
        self.smartCleanupProgress = smartCleanupProgressStore.load()
        self.skippedPhotoRecords = skippedPhotoStore.allRecords()
        super.init()
        PhotoCleanupViewModel.shared = self
        refreshTimeMachineSnapshots()
        setupMetadataPipeline()
        PHPhotoLibrary.shared().register(self)
        if authorizationStatus.isAuthorized {
            ensureMetadataBootstrap()
            if !FeatureToggles.enableZeroLatencyPipeline || !FeatureToggles.lazyLoadPhotoSessions {
                scheduleInitialAssetLoad()
            }
        }
        
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.updateAuthorizationStatus()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        if PhotoCleanupViewModel.shared === self {
            PhotoCleanupViewModel.shared = nil
        }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        Task { await taskPool.cancelAll() }
        Task { await backgroundScheduler.cancelAll() }
    }

    private func setupMetadataPipeline() {
        metadataRepository.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.metadataSnapshot = snapshot
                if FeatureToggles.enableZeroLatencyPipeline {
                    self.monthAssetTotals = snapshot.monthTotalsDictionary
                    if snapshot.deviceStorageUsage.hasValidData {
                        self.deviceStorageUsage = snapshot.deviceStorageUsage
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func ensureMetadataBootstrap() {
        guard FeatureToggles.enableZeroLatencyPipeline else { return }
        metadataRepository.bootstrapIfNeeded()
    }

    private func ensureRealAssetPipeline() {
        guard FeatureToggles.enableZeroLatencyPipeline, FeatureToggles.lazyLoadPhotoSessions else { return }
        scheduleInitialAssetLoad()
    }
    
    // MARK: - Status Updates
    
    private func updateAuthorizationStatus() {
        DispatchQueue.main.async {
            let oldStatus = self.authorizationStatus
            let newStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            self.authorizationStatus = newStatus

            if newStatus != oldStatus && newStatus.isAuthorized {
                self.ensureMetadataBootstrap()
                if !FeatureToggles.enableZeroLatencyPipeline || !FeatureToggles.lazyLoadPhotoSessions {
                    self.scheduleInitialAssetLoad()
                }
            }
        }
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let fetchResult = assetsFetchResult,
              changeInstance.changeDetails(for: fetchResult) != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resetPagingState()
            self.pagingLoader.reloadLibrary()
            self.photoRepository.reloadLibrary()
            if FeatureToggles.enableZeroLatencyPipeline {
                self.metadataRepository.refresh()
            }
        }
    }
    
    // MARK: - Navigation
    
    func showCleaner(filter: CleanupFilterMode) {
        ensureRealAssetPipeline()
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
        ensureRealAssetPipeline()
        activeMonthContext = (year, month)
        rebuildMonthSession(year: year, month: month)
        isShowingCleaner = true
    }

    func prepareSession(with assets: [PHAsset], month: MonthInfo) -> Bool {
        guard !assets.isEmpty else { return false }
        isLoading = true
        let preparedItems = buildPhotoItems(from: assets)
        guard !preparedItems.isEmpty else {
            isLoading = false
            return false
        }
        integratePreparedItems(preparedItems)
        hasInitializedSession = true
        activeMonthContext = (month.year, month.month)
        sessionItems = preparedItems
        sessionItemIds = Set(preparedItems.map(\.id))
        currentFilter = .all
        currentIndex = 0
        isShowingCleaner = true
        isLoading = false
        configureLargeImagePipeline()
        return true
    }
    
    func hideCleaner() {
        isShowingCleaner = false
        activeMonthContext = nil
    }

    func showDetail(_ detail: DashboardDetail) {
        ensureRealAssetPipeline()
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
                if newStatus.isAuthorized {
                    self.ensureMetadataBootstrap()
                    if !FeatureToggles.enableZeroLatencyPipeline || !FeatureToggles.lazyLoadPhotoSessions {
                        self.scheduleInitialAssetLoad()
                    }
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
        Task { await self.photoRepository.bootstrapLibraryIfNeeded() }
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
        if FeatureToggles.enableZeroLatencyPipeline {
            ensureMetadataBootstrap()
            if !FeatureToggles.lazyLoadPhotoSessions {
                scheduleInitialAssetLoad()
            }
        } else {
            scheduleInitialAssetLoad()
            refreshDeviceStorageUsage()
        }
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
        Task { await taskPool.cancel(scope: .prefetch) }
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
        } else if let context = activeMonthContext,
                  incomingContainsItems(forYear: context.year, month: context.month, items: incoming) {
            rebuildMonthSession(year: context.year, month: context.month)
        }
        scheduleBackgroundAnalysisIfNeeded()
    }

    private func incomingContainsItems(forYear year: Int, month: Int, items: [PhotoItem]) -> Bool {
        let calendar = Calendar.current
        return items.contains { item in
            guard let date = item.creationDate else { return false }
            let comps = calendar.dateComponents([.year, .month], from: date)
            return comps.year == year && comps.month == month
        }
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
        guard !hasTriggeredBackgroundAnalysis, !items.isEmpty else { return }
        hasTriggeredBackgroundAnalysis = true
        Task { await backgroundScheduler.cancel(job: .similarity) }
        Task { [weak self] in
            guard let self else { return }
            await self.backgroundScheduler.schedule(job: .similarity) { [weak self] in
                self?.analyzeAllItemsInBackground()
            }
        }
    }

    private func analyzeAllItemsInBackground() {
        guard !items.isEmpty else { return }
        let snapshotItems = self.items
        let cacheSnapshot = analysisCache.snapshot()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var analyzedItems = snapshotItems
            let analysisService = ImageAnalysisService.shared
            let total = analyzedItems.count
            var featurePrints: [VNFeaturePrintObservation?] = Array(repeating: nil, count: total)
            var pHashes: [UInt64?] = Array(repeating: nil, count: total)

            for i in 0..<total {
                let item = analyzedItems[i]
                analyzedItems[i].similarGroupId = nil
                analyzedItems[i].similarityKind = nil
                if let entry = cacheSnapshot[item.id],
                   entry.version == PhotoAnalysisCacheEntry.currentVersion,
                   entry.fileSize == item.fileSize {
                    featurePrints[i] = self.unarchiveFeaturePrint(from: entry.featurePrintData)
                    pHashes[i] = entry.pHash
                    analyzedItems[i].isScreenshot = entry.isScreenshot
                    analyzedItems[i].isDocumentLike = entry.isDocumentLike
                    analyzedItems[i].isTextImage = entry.isTextImage
                    analyzedItems[i].blurScore = entry.blurScore
                    analyzedItems[i].isBlurredOrShaky = entry.isBlurredOrShaky
                    analyzedItems[i].exposureIsBad = entry.exposureIsBad
                    analyzedItems[i].pHash = entry.pHash
                }
            }

            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.resizeMode = .exact
            requestOptions.isNetworkAccessAllowed = true
            let targetSize = CGSize(width: 256, height: 256)

            for index in 0..<analyzedItems.count {
                if featurePrints[index] != nil { continue }
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
                        analyzedItems[index].blurScore = blurScore
                        analyzedItems[index].exposureIsBad = exposureBad
                        analyzedItems[index].isBlurredOrShaky = blurScore < 0.04 || (blurScore < 0.07 && exposureBad)
                        analyzedItems[index].isLargeFile = analyzedItems[index].fileSize > 15 * 1024 * 1024
                        if !analyzedItems[index].isVideo {
                            featurePrints[index] = analysisService.featurePrint(for: image)
                            let hash = analysisService.perceptualHash(for: image)
                            pHashes[index] = hash
                            analyzedItems[index].pHash = hash
                        }
                    } else {
                        analyzedItems[index].isLargeFile = analyzedItems[index].fileSize > 15 * 1024 * 1024
                    }
                }
            }

            self.processSimilarGroups(analyzedItems: &analyzedItems, featurePrints: featurePrints, pHashes: pHashes)

            let cacheEntries = self.buildCacheEntries(from: analyzedItems, featurePrints: featurePrints, pHashes: pHashes)
            self.analysisCache.update(entries: cacheEntries)

            DispatchQueue.main.async {
                self.items = analyzedItems
                self.revalidateSimilarGroups()
                self.refreshSession()
                self.hasTriggeredBackgroundAnalysis = false
            }
        }
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
        if let index = items.firstIndex(where: { $0.id == currentItem.id }) {
            items[index].markedForDeletion = true
            persistSelectionState(for: items[index])
            syncSmartCleanupPendingFlag()
        }
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
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion.toggle()
            persistSelectionState(for: items[index])
            syncSmartCleanupPendingFlag()
            refreshSession() // Refresh session to exclude已删除
        }
    }

    func setDeletion(_ item: PhotoItem, to flag: Bool) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion = flag
            persistSelectionState(for: items[index])
            syncSmartCleanupPendingFlag()
            refreshSession()
        }
    }

    func removeFromPending(_ item: PhotoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion = false
            persistSelectionState(for: items[index])
            syncSmartCleanupPendingFlag()
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
            syncSmartCleanupPendingFlag()
            refreshSession()
        }
    }
    
    func resetCleanupProgress() {
        timeMachineProgressStore.resetAll()
        refreshTimeMachineSnapshots()
        storeSmartCleanupProgress(nil)
        activeMonthContext = nil
        currentIndex = 0
        refreshSession()
    }
    
    func resetSmartCleanupProgressOnly() {
        storeSmartCleanupProgress(nil)
    }
    
    func resetTimeMachineProgress() {
        timeMachineProgressStore.resetAll()
        refreshTimeMachineSnapshots()
        if let context = activeMonthContext {
            rebuildMonthSession(year: context.year, month: context.month)
        } else {
            refreshSession()
        }
    }

    func timeMachineProgress(year: Int, month: Int) -> TimeMachineMonthProgress? {
        timeMachineProgressStore.progress(year: year, month: month)
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
            creationDate: asset.creationDate ?? asset.modificationDate,
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
    }

    private func restoreSelectionStates(in items: inout [PhotoItem]) {
        for index in items.indices {
            guard
                let comps = monthComponents(for: items[index]),
                let progress = timeMachineProgressStore.progress(year: comps.year, month: comps.month)
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
    
    private func storeSmartCleanupProgress(_ progress: SmartCleanupProgress?) {
        smartCleanupProgress = progress
        smartCleanupProgressStore.save(progress)
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
        skippedPhotoRecords = skippedPhotoStore.allRecords()
    }

    private func refreshTimeMachineSnapshots() {
        let progresses = timeMachineProgressStore.allProgresses()
        var snapshot: [String: TimeMachineMonthProgress] = [:]
        progresses.forEach { snapshot[$0.key] = $0 }
        timeMachineSnapshots = snapshot
    }

    func logSkippedPhoto(_ item: PhotoItem, source: SkippedPhotoSource) {
        skippedPhotoStore.record(photoId: item.id, source: source)
        refreshSkippedPhotoRecords()
    }

    func markSkippedRecordsProcessed(ids: [String]) {
        guard !ids.isEmpty else { return }
        skippedPhotoStore.markProcessed(ids: ids)
        refreshSkippedPhotoRecords()
    }

    func deleteSkippedRecords(ids: [String]) {
        guard !ids.isEmpty else { return }
        skippedPhotoStore.remove(ids: ids)
        refreshSkippedPhotoRecords()
    }

    func clearSkippedRecords() {
        skippedPhotoStore.clear()
        refreshSkippedPhotoRecords()
    }
    
    func confirmDeletionForSkipped(ids: [String]) {
        guard !ids.isEmpty else { return }
        var updated = false
        for id in ids {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].markedForDeletion = true
                persistSelectionState(for: items[index])
                updated = true
            }
        }
        if updated {
            syncSmartCleanupPendingFlag()
            refreshSession()
        }
        skippedPhotoStore.remove(ids: ids)
        refreshSkippedPhotoRecords()
    }
    
    func reinstateSkippedPhotos(ids: [String]) {
        guard !ids.isEmpty else { return }
        skippedPhotoStore.remove(ids: ids)
        refreshSkippedPhotoRecords()
    }
    
    func acknowledgeSkippedPhotos(ids: [String]) {
        guard !ids.isEmpty else { return }
        skippedPhotoStore.remove(ids: ids)
        refreshSkippedPhotoRecords()
    }

    private func persistSelectionState(for item: PhotoItem) {
        guard let comps = monthComponents(for: item) else { return }
        timeMachineProgressStore.setPhoto(item.id, year: comps.year, month: comps.month, markedForDeletion: item.markedForDeletion)
        refreshTimeMachineSnapshots()
    }

    private func recordConfirmation(for item: PhotoItem) {
        guard let comps = monthComponents(for: item) else { return }
        timeMachineProgressStore.confirmPhoto(item.id, year: comps.year, month: comps.month)
        refreshTimeMachineSnapshots()
    }

    private func clearStoredRecords(for items: [PhotoItem]) {
        for item in items {
            guard let comps = monthComponents(for: item) else { continue }
            timeMachineProgressStore.removePhotoRecords(item.id, year: comps.year, month: comps.month)
        }
        refreshTimeMachineSnapshots()
    }

    private func monthComponents(for item: PhotoItem) -> (year: Int, month: Int)? {
        let date = item.creationDate ?? item.asset.creationDate ?? item.asset.modificationDate
        guard let date else { return nil }
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
        let key = "\(year)-\(month)"
        let filtered = items.filter { item in
            guard !item.markedForDeletion, let date = item.creationDate else { return false }
            let comps = calendar.dateComponents([.year, .month], from: date)
            guard comps.year == year && comps.month == month else { return false }
            return !isPhotoDeferredInTimeMachine(item)
        }
        let sorted = filtered.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        #if DEBUG
        let totalInMonth = items.filter { item in
            guard let date = item.creationDate else { return false }
            let comps = calendar.dateComponents([.year, .month], from: date)
            return comps.year == year && comps.month == month
        }.count
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
        let base = collection.filter { !$0.markedForDeletion && !isPhotoDeferredInTimeMachine($0) && isItemInSelectedAlbum($0) }
        switch filter {
        case .all:
            return base
        case .similar:
            return base.filter { $0.similarGroupId != nil }
        case .blurred:
            return base.filter { $0.isBlurredOrShaky }
        case .screenshots:
            return base.filter { $0.isScreenshot || $0.isDocumentLike }
        case .documents:
            return base.filter { $0.isDocumentLike }
        case .large:
            return base.filter { $0.isLargeFile }
        }
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
        Task { await self.photoRepository.bootstrapLibraryIfNeeded() }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var identifiers: Set<String> = []
            fetchResult.enumerateObjects { asset, _, _ in
                identifiers.insert(asset.localIdentifier)
            }
            self?.analysisCache.pruneMissingEntries(keeping: identifiers)
        }
        if !FeatureToggles.enableZeroLatencyPipeline {
            rebuildMonthAssetTotals(from: fetchResult)
        }
    }

    func photoLoader(_ loader: PhotoLoader, didLoadAssets assets: [PHAsset]) {
        ingestAssets(assets)
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
        let key = "\(year)-\(month)"
        guard !monthPrefetchingKeys.contains(key) else { return }
        monthPrefetchingKeys.insert(key)

        if FeatureToggles.enableZeroLatencyPipeline {
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                let momentIds = self.metadataSnapshot.monthMomentIdentifiers[key] ?? []
                let descriptors: [AssetDescriptor]
                if !momentIds.isEmpty {
                    descriptors = await self.photoRepository.fetchAssets(forMomentIdentifiers: momentIds, limit: 400)
                } else {
                    descriptors = await self.photoRepository.prefetchMonth(year, month: month, limit: 400)
                }
                guard !Task.isCancelled else { return }
                let assets = descriptors.map(\.asset)
                await MainActor.run {
                    self.ingestAssets(assets)
                    self.monthPrefetchingKeys.remove(key)
                }
                self.imagePipeline.prefetch(assets, targetSize: CGSize(width: 280, height: 280))
            }
            Task { [weak self] in
                guard let self else { return }
                await self.taskPool.insert(task, scope: .prefetch)
            }
            return
        }

        guard let fetchResult = assetsFetchResult else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let assets = self.assets(in: fetchResult, year: year, month: month)
            let limitedAssets = Array(assets.prefix(400))
            DispatchQueue.main.async {
                self.ingestAssets(limitedAssets)
                self.monthPrefetchingKeys.remove(key)
            }
        }
    }

    private func buildPhotoItems(from assets: [PHAsset]) -> [PhotoItem] {
        guard !assets.isEmpty else { return [] }
        let cacheEntries = analysisCache.snapshot()
        var incoming: [PhotoItem] = []
        for asset in assets {
            let estimatedSize = assetResourceSize(for: asset)
            var item = photoItem(for: asset, estimatedSize: estimatedSize)
            let id = item.id
            if let entry = cacheEntries[id],
               entry.version == PhotoAnalysisCacheEntry.currentVersion,
               entry.fileSize == item.fileSize {
                applyCachedEntry(entry, to: &item)
            }
            incoming.append(item)
        }
        restoreSelectionStates(in: &incoming)
        return incoming.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    private func integratePreparedItems(_ newItems: [PhotoItem]) {
        guard !newItems.isEmpty else { return }
        var indexMap: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            indexMap[item.id] = index
        }
        for item in newItems {
            loadedAssetIdentifiers.insert(item.id)
            if let idx = indexMap[item.id] {
                items[idx] = item
            } else {
                indexMap[item.id] = items.count
                items.append(item)
            }
        }
    }

    private func configureLargeImagePipeline() {
        guard isZeroLatencyTimeMachineSession else {
            largeImageCache.removeAll()
            return
        }
        let assets = sessionItems.map(\.asset)
        let target = largeImageTargetSize
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.largeImagePager.configure(assets: assets, targetSize: target)
            let cache = await self.largeImagePager.ensureWindow(centerIndex: self.currentIndex)
            await MainActor.run {
                self.largeImageCache = cache
            }
        }
    }

    private func updateLargeImageWindowIfNeeded(center: Int) {
        guard isZeroLatencyTimeMachineSession else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let cache = await self.largeImagePager.ensureWindow(centerIndex: center)
            await MainActor.run {
                self.largeImageCache = cache
            }
        }
    }

    private var largeImageTargetSize: CGSize {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}
