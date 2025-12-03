import SwiftUI
import Combine
import Photos
import Vision
import UIKit

enum SessionPreparationResult {
    case success
    case cancelled
    case failed
}

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
            updateThumbnailWindowIfNeeded(center: currentIndex)
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
    private let thumbnailStore = ThumbnailStore()
    private let largeImagePager = LargeImagePager()
    private let fullImageStore = FullImageStore()
    private let sessionManager: PhotoSessionManager
    private let backgroundScheduler = BackgroundJobScheduler()
    private let analysisChunkSize = 24
    private let baseAnalysisPause: UInt64 = 120_000_000
    private var assetsFetchResult: PHFetchResult<PHAsset>?
    private var cancellables: Set<AnyCancellable> = []
    private var hasTriggeredBackgroundAnalysis = false
    private var allowBackgroundAnalysis = false
    private var selectedAlbumAssetIds: Set<String>?
    private var hasLoadedAlbumFilters = false
    private var sessionPreparationTask: Task<SessionPreparationResult, Never>?
    private var sessionPreparationToken: UUID?
    private var activeSession: PhotoSession?
    private var allSession: PhotoSession?
    private var hasPrewarmedAllSession = false
    private var sessionTrimmedCounts: [UUID: Int] = [:]
    private let sessionBufferThreshold = 4
    private let swipeThrottleInterval: TimeInterval = 0.25
    private var lastActionTimestamp: TimeInterval = 0

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
        self.sessionManager = PhotoSessionManager(
            photoRepository: photoRepository,
            analysisCache: analysisCache,
            thumbnailStore: thumbnailStore
        )
        super.init()
        PhotoCleanupViewModel.shared = self
        sessionManager.delegate = self
        refreshTimeMachineSnapshots()
        setupMetadataPipeline()
        PHPhotoLibrary.shared().register(self)
        if authorizationStatus.isAuthorized {
            ensureMetadataBootstrap()
            loadAlbumFiltersIfNeeded()
            refreshAssetsFetchResult()
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
        let scheduler = backgroundScheduler
        let pager = largeImagePager
        Task.detached {
            await scheduler.cancelAll()
        }
        Task.detached {
            await pager.configure(assets: [], targetSize: .zero)
        }
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

    private func refreshAssetsFetchResult() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        assetsFetchResult = PHAsset.fetchAssets(with: options)
    }

    // MARK: - Status Updates
    
    private func updateAuthorizationStatus() {
        DispatchQueue.main.async {
            let oldStatus = self.authorizationStatus
            let newStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            self.authorizationStatus = newStatus

            if newStatus != oldStatus && newStatus.isAuthorized {
                self.ensureMetadataBootstrap()
                self.loadAlbumFiltersIfNeeded()
                self.refreshAssetsFetchResult()
            }
        }
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let fetchResult = assetsFetchResult,
              let details = changeInstance.changeDetails(for: fetchResult) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.assetsFetchResult = details.fetchResultAfterChanges
            if let updatedResult = self.assetsFetchResult {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    var identifiers: Set<String> = []
                    updatedResult.enumerateObjects { asset, _, _ in
                        identifiers.insert(asset.localIdentifier)
                    }
                    self?.analysisCache.pruneMissingEntries(keeping: identifiers)
                }
            }
            self.resetSessionState()
            self.photoRepository.reloadLibrary()
            self.sessionManager.resetSessions()
            self.metadataRepository.refresh()
        }
    }
    
    // MARK: - Navigation
    
    func showCleaner(filter: CleanupFilterMode) {
        allowBackgroundAnalysis = true
        prewarmAllSessionIfNeeded()
        activeMonthContext = nil
        activateFilterSession(filter: filter)
        isShowingCleaner = true
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
        allowBackgroundAnalysis = true
        prewarmAllSessionIfNeeded()
        activeMonthContext = (year, month)
        rebuildMonthSession(year: year, month: month)
        isShowingCleaner = true
    }

    func makeZeroLatencyTimeMachineViewModel() -> TimeMachineZeroLatencyViewModel {
        TimeMachineZeroLatencyViewModel(
            metadataRepository: metadataRepository,
            analysisCache: analysisCache,
            thumbnailStore: thumbnailStore
        )
    }

    func thumbnail(for assetId: String, target: ThumbnailTarget) async -> UIImage? {
        await thumbnailStore.thumbnail(for: assetId, target: target)
    }

    func requestFullImage(for assetId: String) {
        guard FeatureToggles.enableApplePhotosArchitecture, let index = sessionItems.firstIndex(where: { $0.id == assetId }) else { return }
        updateLargeImageWindowIfNeeded(center: index)
    }

    func preloadThumbnails(for assetIds: [String], target: ThumbnailTarget) {
        guard !assetIds.isEmpty else { return }
        Task {
            await thumbnailStore.preload(assetIds: assetIds, target: target)
        }
    }

    func preloadSampleThumbnails(for filter: CleanupFilterMode, limit: Int = 12, target: ThumbnailTarget = .dashboardCard) {
        let ids = sampleAssetIdentifiers(for: filter, limit: limit)
        preloadThumbnails(for: ids, target: target)
    }

    func prepareSession(with assets: [PHAsset], month: MonthInfo) async -> SessionPreparationResult {
        guard !assets.isEmpty else { return .failed }
        cancelSessionPreparation()
        let token = UUID()
        sessionPreparationToken = token
        let task = Task(priority: .userInitiated) { [weak self] () -> SessionPreparationResult in
            guard let self else { return .failed }
            return await self.prepareSessionInternal(assets: assets, month: month)
        }
        sessionPreparationTask = task
        let result = await task.value
        if sessionPreparationToken == token {
            sessionPreparationTask = nil
            sessionPreparationToken = nil
        }
        return result
    }
    
    func hideCleaner() {
        isShowingCleaner = false
        activeMonthContext = nil
        allowBackgroundAnalysis = false
        if let session = activeSession {
            Task { await fullImageStore.reset(sessionId: session.id) }
            sessionTrimmedCounts.removeValue(forKey: session.id)
        }
        activeSession = nil
        cancelSessionPreparation()
        Task { await resetLargeImagePipeline() }
    }

    func showDetail(_ detail: DashboardDetail) {
        activeDetail = detail
    }

    func dismissDetail() {
        activeDetail = nil
    }

    private func prepareSessionInternal(assets: [PHAsset], month: MonthInfo) async -> SessionPreparationResult {
        await MainActor.run {
            self.activeMonthContext = (month.year, month.month)
            self.sessionItems = []
            self.currentFilter = .all
            self.currentIndex = 0
            self.isShowingCleaner = true
            self.isLoading = true
        }
        let cacheSnapshot = analysisCache.snapshot()
        let preparedItems = PhotoCleanupViewModel.buildZeroLatencyItems(from: assets, cache: cacheSnapshot)
        if Task.isCancelled { return .cancelled }
        guard !preparedItems.isEmpty else {
            await MainActor.run {
                self.isShowingCleaner = false
                self.isLoading = false
            }
            return .failed
        }
        await MainActor.run {
            self.integratePreparedItems(preparedItems)
            self.sessionItems = preparedItems
            self.currentFilter = .all
            self.currentIndex = 0
            self.scheduleBackgroundAnalysisIfNeeded()
        }
        preloadThumbnails(for: preparedItems.prefix(10).map(\.id), target: .tinderCard)
        if Task.isCancelled { return .cancelled }
        await configureLargeImagePipeline()
        if Task.isCancelled { return .cancelled }
        await MainActor.run { self.isLoading = false }
        return .success
    }

    // MARK: - Session Management

    func updateSessionItems(for filter: CleanupFilterMode) {
        currentFilter = filter
        rebuildActiveSessionItems(resetIndex: true)
    }

    func refreshSession() {
        rebuildActiveSessionItems(resetIndex: false)
    }

    func selectAlbumFilter(_ filter: AlbumFilter) {
        guard selectedAlbumFilter != filter else { return }
        selectedAlbumFilter = filter
        if let collection = filter.collection {
            selectedAlbumAssetIds = nil
            sessionItems = []
            currentIndex = 0
            Task.detached { [weak self] in
                guard let self else { return }
                let ids = await self.fetchAssetIdentifiers(in: collection)
                await MainActor.run {
                    self.selectedAlbumAssetIds = ids
                    self.rebuildActiveSessionItems(resetIndex: true)
                }
            }
        } else {
            selectedAlbumAssetIds = nil
            rebuildActiveSessionItems(resetIndex: true)
        }
    }

    private func rebuildActiveSessionItems(resetIndex: Bool) {
        let base: [PhotoItem]
        if let context = activeMonthContext {
            base = monthItems(year: context.year, month: context.month)
        } else {
            base = filteredItems(for: currentFilter, from: items)
        }
        sessionItems = base
        if resetIndex {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, max(sessionItems.count - 1, 0))
        }
    }

    // MARK: - Data Loading & Analysis

    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorizationStatus = newStatus
                if newStatus.isAuthorized {
                    self.ensureMetadataBootstrap()
                    self.loadAlbumFiltersIfNeeded()
                    self.refreshAssetsFetchResult()
                }
            }
        }
    }

    func ensureAssetsPrepared() {
        if FeatureToggles.enableZeroLatencyPipeline {
            ensureMetadataBootstrap()
            loadAlbumFiltersIfNeeded()
            refreshAssetsFetchResult()
        } else {
            refreshDeviceStorageUsage()
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

    private func resetSessionState() {
        hasTriggeredBackgroundAnalysis = false
        items = []
        sessionItems = []
        currentIndex = 0
        currentFilter = .all
        activeSession = nil
        allSession = nil
        hasPrewarmedAllSession = false
        cancelSessionPreparation()
        Task { await resetLargeImagePipeline() }
        Task { await thumbnailStore.resetCache() }
        sessionTrimmedCounts.removeAll()
    }

    private func prewarmAllSessionIfNeeded() {
        guard FeatureToggles.enableApplePhotosArchitecture else { return }
        guard !hasPrewarmedAllSession else { return }
        hasPrewarmedAllSession = true
        let session = sessionManager.session(scope: .all)
        allSession = session
        sessionTrimmedCounts[session.id] = session.state.trimmedCount
        if session.state.items.isEmpty {
            Task { await sessionManager.loadNextBatch(for: session) }
        } else {
            Task { @MainActor in
                self.applyAllSessionItems(session)
            }
        }
    }

    private func cancelSessionPreparation() {
        sessionPreparationTask?.cancel()
        sessionPreparationTask = nil
        sessionPreparationToken = nil
    }

    static func applyCachedEntry(_ entry: PhotoAnalysisCacheEntry, to item: inout PhotoItem) {
        PhotoItemFactory.applyCachedEntry(entry, to: &item)
    }

    private func scheduleBackgroundAnalysisIfNeeded() {
        guard allowBackgroundAnalysis, !hasTriggeredBackgroundAnalysis, !items.isEmpty else { return }
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
        Task.detached(priority: .utility) { [weak self] in
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
            requestOptions.deliveryMode = .fastFormat
            requestOptions.resizeMode = .fast
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
                if (index + 1) % self.analysisChunkSize == 0 {
                    let interval = self.analysisPauseInterval()
                    if interval > 0 {
                        try? await Task.sleep(nanoseconds: interval)
                    }
                }
            }

            self.processSimilarGroups(analyzedItems: &analyzedItems, featurePrints: featurePrints, pHashes: pHashes)

            let cacheEntries = self.buildCacheEntries(from: analyzedItems, featurePrints: featurePrints, pHashes: pHashes)
            self.analysisCache.update(entries: cacheEntries)

            await MainActor.run {
                self.items = analyzedItems
                self.revalidateSimilarGroups()
                self.refreshSession()
                self.hasTriggeredBackgroundAnalysis = false
            }
        }
    }

    private func analysisPauseInterval() -> UInt64 {
        let thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .critical:
            return baseAnalysisPause * 6
        case .serious:
            return baseAnalysisPause * 4
        case .fair:
            return baseAnalysisPause * 2
        default:
            return baseAnalysisPause
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
        ensureCleanerBufferIfNeeded()
    }

    private func removeCurrentItemFromSession() {
        guard !sessionItems.isEmpty else {
            return
        }
        let removedIndex = currentIndex
        sessionItems.remove(at: removedIndex)
        if sessionItems.isEmpty {
            currentIndex = 0
        } else if currentIndex >= sessionItems.count {
            currentIndex = max(sessionItems.count - 1, 0)
        }
        ensureCleanerBufferIfNeeded()
    }

    private func ensureCleanerBufferIfNeeded() {
        guard FeatureToggles.enableApplePhotosArchitecture,
              let session = activeSession,
              !session.state.isExhausted else { return }
        let remaining = max(sessionItems.count - currentIndex, 0)
        if remaining <= sessionBufferThreshold {
            Task { await sessionManager.loadNextBatch(for: session) }
        }
    }

    private func removeItemFromGlobalCollection(item: PhotoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        }
    }

    private func shouldThrottleUserAction() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastActionTimestamp < swipeThrottleInterval {
            return true
        }
        lastActionTimestamp = now
        return false
    }

    func markCurrentForDeletion() {
        guard let currentItem = currentItem else { return }
        guard !shouldThrottleUserAction() else { return }
        if let index = items.firstIndex(where: { $0.id == currentItem.id }) {
            items[index].markedForDeletion = true
            persistSelectionState(for: items[index])
            syncSmartCleanupPendingFlag()
        }
        moveToNext()
    }

    func keepCurrent() {
        guard let currentItem = currentItem else { return }
        guard !shouldThrottleUserAction() else { return }
        recordConfirmation(for: currentItem)
        removeCurrentItemFromSession()
        removeItemFromGlobalCollection(item: currentItem)
    }
    
    func skipCurrent() {
        guard let currentItem = currentItem else { return }
        guard !shouldThrottleUserAction() else { return }
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
    
    private static func makePhotoItem(for asset: PHAsset, estimatedSize: Int) -> PhotoItem {
        PhotoItemFactory.makePhotoItem(for: asset, estimatedSize: estimatedSize)
    }
    
    func photoItem(for asset: PHAsset, estimatedSize: Int) -> PhotoItem {
        if let existing = items.first(where: { $0.id == asset.localIdentifier }) {
            return existing
        }
        return PhotoItemFactory.makePhotoItem(for: asset, estimatedSize: estimatedSize)
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
        activateMonthSession(year: year, month: month)
    }

    private func activateMonthSession(year: Int, month: Int) {
        let scope = PhotoSessionScope.month(year: year, month: month)
        activateSession(scope: scope, filter: .all)
    }

    private func activateFilterSession(filter: CleanupFilterMode) {
        let scope: PhotoSessionScope = filter == .all ? .all : .filter(filter)
        activateSession(scope: scope, filter: filter)
    }

    private func activateSession(scope: PhotoSessionScope, filter: CleanupFilterMode) {
        currentFilter = filter
        let session = sessionManager.session(scope: scope)
        activeSession = session
        sessionTrimmedCounts[session.id] = session.state.trimmedCount
        if session.state.items.isEmpty {
            sessionItems = []
            currentIndex = 0
            Task {
                await sessionManager.loadNextBatch(for: session)
            }
        } else {
            applyRestoredSessionItems(from: session)
        }
    }

    private func applyRestoredSessionItems(from session: PhotoSession) {
        var restored = session.state.items
        restoreSelectionStates(in: &restored)
        integratePreparedItems(restored)
        let shouldReset = sessionItems.isEmpty
        rebuildActiveSessionItems(resetIndex: shouldReset)
        Task { await configureLargeImagePipeline() }
    }

    @MainActor
    private func applyAllSessionItems(_ session: PhotoSession) {
        var restored = session.state.items
        restoreSelectionStates(in: &restored)
        items = restored
        if !isShowingCleaner {
            rebuildActiveSessionItems(resetIndex: false)
        }
        scheduleBackgroundAnalysisIfNeeded()
    }

    private func restoreSelectionStates(in items: inout [PhotoItem]) {
        let pendingIds = Set(self.pendingDeletionItems.map { $0.id })
        let skippedIds = Set(timeMachineSkippedPhotoIds)
        for index in items.indices {
            let id = items[index].id
            if pendingIds.contains(id) || skippedIds.contains(id) {
                items[index].markedForDeletion = true
                continue
            }
            if
                let comps = monthComponents(for: items[index]),
                let progress = timeMachineProgressStore.progress(year: comps.year, month: comps.month),
                progress.selectedPhotoIds.contains(id)
            {
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
        let filtered = items.filter { item in
            guard !item.markedForDeletion,
                  let date = item.creationDate else { return false }
            let comps = calendar.dateComponents([.year, .month], from: date)
            guard comps.year == year, comps.month == month else { return false }
            return !isPhotoDeferredInTimeMachine(item) && isItemInSelectedAlbum(item)
        }
        return filtered.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
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

    private func sampleAssetIdentifiers(for filter: CleanupFilterMode, limit: Int) -> [String] {
        let filtered = filteredItems(for: filter, from: items)
        return filtered.prefix(limit).map(\.id)
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
        Self.assetResourceSizeStatic(for: asset)
    }

    nonisolated private static func assetResourceSizeStatic(for asset: PHAsset) -> Int {
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

extension PhotoCleanupViewModel {
    private func integratePreparedItems(_ newItems: [PhotoItem]) {
        guard !newItems.isEmpty else { return }
        var indexMap: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            indexMap[item.id] = index
        }
        for item in newItems {
            if let idx = indexMap[item.id] {
                items[idx] = item
            } else {
                indexMap[item.id] = items.count
                items.append(item)
            }
        }
    }

    private static func buildZeroLatencyItems(
        from assets: [PHAsset],
        cache: [String: PhotoAnalysisCacheEntry]
    ) -> [PhotoItem] {
        guard !assets.isEmpty else { return [] }
        var incoming: [PhotoItem] = []
        for asset in assets {
            if Task.isCancelled { return [] }
            let estimatedSize = assetResourceSizeStatic(for: asset)
            var item = Self.makePhotoItem(for: asset, estimatedSize: estimatedSize)
            let id = item.id
            if let entry = cache[id],
               entry.version == PhotoAnalysisCacheEntry.currentVersion,
               entry.fileSize == item.fileSize {
                Self.applyCachedEntry(entry, to: &item)
            }
            incoming.append(item)
        }
        return incoming.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    private func configureLargeImagePipeline() async {
        if FeatureToggles.enableApplePhotosArchitecture, let session = activeSession {
            let assets = session.state.items.map(\.asset)
            let cache = await fullImageStore.configure(sessionId: session.id, assets: assets, targetSize: largeImageTargetSize)
            await MainActor.run {
                guard PhotoCleanupViewModel.shared === self else { return }
                self.largeImageCache = cache
            }
            return
        }
        guard isZeroLatencyTimeMachineSession else {
            await resetLargeImagePipeline()
            return
        }
        let assets = sessionItems.map(\.asset)
        let target = largeImageTargetSize
        await largeImagePager.configure(assets: assets, targetSize: target)
        let cache = await largeImagePager.ensureWindow(centerIndex: currentIndex)
        await MainActor.run {
            guard PhotoCleanupViewModel.shared === self else { return }
            self.largeImageCache = cache
        }
    }

    private func updateLargeImageWindowIfNeeded(center: Int) {
        if FeatureToggles.enableApplePhotosArchitecture, let session = activeSession {
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let cache = await self.fullImageStore.ensureWindow(sessionId: session.id, centerIndex: center)
                await MainActor.run {
                    self.largeImageCache = cache
                }
            }
            return
        }
        guard isZeroLatencyTimeMachineSession else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let cache = await self.largeImagePager.ensureWindow(centerIndex: center)
            await MainActor.run {
                self.largeImageCache = cache
            }
        }
    }

    private func updateThumbnailWindowIfNeeded(center: Int) {
        if FeatureToggles.enableApplePhotosArchitecture, let session = activeSession {
            if center >= max(session.state.items.count - 3, 0), !session.state.isExhausted {
                Task { await sessionManager.loadNextBatch(for: session) }
            }
        }
        guard !sessionItems.isEmpty else { return }
        let lower = max(0, center - 5)
        let upper = min(sessionItems.count - 1, center + 8)
        guard lower <= upper else { return }
        let ids = (lower...upper).compactMap { sessionItems[safe: $0]?.id }
        preloadThumbnails(for: ids, target: .tinderCard)
    }

    private var largeImageTargetSize: CGSize {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    private func resetLargeImagePipeline() async {
        if FeatureToggles.enableApplePhotosArchitecture, let session = activeSession {
            await fullImageStore.reset(sessionId: session.id)
        } else {
            await largeImagePager.configure(assets: [], targetSize: .zero)
        }
        await MainActor.run {
            guard PhotoCleanupViewModel.shared === self else { return }
            self.largeImageCache.removeAll()
        }
    }
}

extension PhotoCleanupViewModel: PhotoSessionManagerDelegate {
    func photoSessionManager(_ manager: PhotoSessionManager, didUpdate session: PhotoSession) {
        guard FeatureToggles.enableApplePhotosArchitecture else { return }
        if session.id == allSession?.id {
            sessionTrimmedCounts[session.id] = session.state.trimmedCount
            Task { @MainActor in
                self.applyAllSessionItems(session)
            }
        }
        guard session.id == activeSession?.id else { return }
        let previousTrim = sessionTrimmedCounts[session.id] ?? 0
        let currentTrim = session.state.trimmedCount
        let trimmedDelta = max(currentTrim - previousTrim, 0)
        sessionTrimmedCounts[session.id] = currentTrim
        Task { @MainActor in
            self.applyRestoredSessionItems(from: session)
            if trimmedDelta > 0 {
                self.currentIndex = max(self.currentIndex - trimmedDelta, 0)
            } else {
                self.currentIndex = min(self.currentIndex, max(self.sessionItems.count - 1, 0))
            }
            self.updateThumbnailWindowIfNeeded(center: self.currentIndex)
            Task { await self.configureLargeImagePipeline() }
        }
    }
}
