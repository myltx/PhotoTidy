import SwiftUI
import Combine
import Photos
import Vision

final class PhotoCleanupViewModel: ObservableObject {
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
    @Published var items: [PhotoItem] = []
    @Published var sessionItems: [PhotoItem] = []
    
    // Navigation & Session State
    @Published var currentTab: AppView = .dashboard
    @Published var isShowingCleaner: Bool = false
    @Published var activeDetail: DashboardDetail?
    
    @Published var currentFilter: CleanupFilterMode = .all
    @Published var currentIndex: Int = 0

    // Services
    let imageManager = PHCachingImageManager()

    // MARK: - Computed Properties
    
    // Session Items
    var currentItem: PhotoItem? { sessionItems[safe: currentIndex] }
    var nextItem: PhotoItem? { sessionItems[safe: currentIndex + 1] }
    var thirdItem: PhotoItem? { sessionItems[safe: currentIndex + 2] }

    // Dashboard Stats
    var similarItemsCount: Int { items.filter { $0.similarGroupId != nil }.count }
    var blurredItemsCount: Int { items.filter { $0.isBlurredOrShaky }.count }
    var screenshotItemsCount: Int { items.filter { $0.isScreenshot || $0.isDocumentLike }.count }
    var largeFilesSize: Int { items.filter { $0.isLargeFile }.map { $0.fileSize }.reduce(0, +) }

    // Pending Deletion
    var pendingDeletionItems: [PhotoItem] { items.filter { $0.markedForDeletion }.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) } }
    var pendingDeletionTotalSize: Int { pendingDeletionItems.map { $0.fileSize }.reduce(0, +) }

    // MARK: - Initialization
    
    init() {
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadAssets()
        }
    }
    
    // MARK: - Navigation
    
    func showCleaner(filter: CleanupFilterMode) {
        updateSessionItems(for: filter)
        isShowingCleaner = true
    }
    
    func hideCleaner() {
        isShowingCleaner = false
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
        updateSessionItems(for: self.currentFilter)
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
            allResult.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                let fileSize = (resources.first?.value(forKey: "fileSize") as? Int) ?? 0
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
            
            DispatchQueue.main.async {
                self.items = loadedItems
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var analyzedItems = snapshotItems
            let analysisService = ImageAnalysisService.shared
            let total = analyzedItems.count
            var featurePrints: [VNFeaturePrintObservation?] = Array(repeating: nil, count: total)
            var pHashes: [UInt64?] = Array(repeating: nil, count: total)

            // 重置相似分组相关字段
            if !analyzedItems.isEmpty {
                for i in 0..<analyzedItems.count {
                    analyzedItems[i].similarGroupId = nil
                    analyzedItems[i].similarityKind = nil
                    analyzedItems[i].pHash = nil
                }
            }

            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.resizeMode = .exact
            requestOptions.isNetworkAccessAllowed = true
            let targetSize = CGSize(width: 256, height: 256)

            for (index, item) in analyzedItems.enumerated() {
                autoreleasepool {
                    var thumbnail: UIImage?
                    let semaphore = DispatchSemaphore(value: 0)
                    self.imageManager.requestImage(
                        for: item.asset,
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

                        analyzedItems[index].isLargeFile = item.fileSize > 15 * 1024 * 1024

                        if !item.isVideo {
                            featurePrints[index] = analysisService.featurePrint(for: image)
                            let hash = analysisService.perceptualHash(for: image)
                            pHashes[index] = hash
                            analyzedItems[index].pHash = hash

                            // 使用 AssetTypeDetector 进行截图 / 文档 / 文字图片 分类
                            if #available(iOS 16.0, *), let cgImage = image.cgImage {
                                let type = AssetTypeDetector.shared.detectAssetTypeSync(asset: item.asset, image: cgImage)
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
                            } else if !item.isScreenshot {
                                // 老设备或无法使用 Vision：退化为原有的文档检测逻辑
                                let isDoc = analysisService.isDocumentLike(image: image)
                                analyzedItems[index].isDocumentLike = isDoc
                            }
                        }
                    } else {
                        // 缩略图获取失败，至少把大文件标记逻辑跑一下
                        analyzedItems[index].isLargeFile = item.fileSize > 15 * 1024 * 1024
                    }

                    let progress = Double(index + 1) / Double(total)
                    // Throttle UI updates to avoid flooding the main thread
                    if index % 15 == 0 || index == total - 1 {
                        DispatchQueue.main.async {
                            self.analysisProgress = progress
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
        if currentIndex < sessionItems.count - 1 {
            currentIndex += 1
        } else {
            // Handle end of stack
            currentIndex = sessionItems.count
        }
    }

    func markCurrentForDeletion() {
        guard let currentItem = currentItem else { return }
        if let index = items.firstIndex(where: { $0.id == currentItem.id }) {
            items[index].markedForDeletion = true
        }
        moveToNext()
    }

    func keepCurrent() {
        // No change needed, just move to the next item
        moveToNext()
    }
    
    func toggleDeletion(for item: PhotoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion.toggle()
            refreshSession() // Refresh session to exclude已删除
        }
    }

    func setDeletion(_ item: PhotoItem, to flag: Bool) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion = flag
            refreshSession()
        }
    }

    func removeFromPending(_ item: PhotoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion = false
            refreshSession()
        }
    }

    func performDeletion(completion: @escaping (Bool, Error?) -> Void) {
        let toDeleteAssets = items.filter { $0.markedForDeletion }.map { $0.asset }
        guard !toDeleteAssets.isEmpty else {
            completion(true, nil)
            return
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(toDeleteAssets as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    let toDeleteIds = Set(toDeleteAssets.map { $0.localIdentifier })
                    self.items.removeAll { toDeleteIds.contains($0.id) }
                    self.refreshSession()
                }
                completion(success, error)
            }
        }
    }
}
