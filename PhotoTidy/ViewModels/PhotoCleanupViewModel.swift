import SwiftUI
import Combine
import Photos
import Vision

final class PhotoCleanupViewModel: ObservableObject {
    // MARK: - Properties
    
    // Publishers
    let objectWillChange = ObservableObjectPublisher()

    // Status
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var isLoading: Bool = false
    @Published var isAnalyzing: Bool = false
    @Published var analysisProgress: Double = 0

    // Data
    @Published var items: [PhotoItem] = []
    @Published var sessionItems: [PhotoItem] = []
    
    // Navigation & Session State
    @Published var currentTab: AppView = .dashboard
    @Published var isShowingCleaner: Bool = false
    @Published var isShowingTrash: Bool = false
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

    func showTrash() {
        isShowingTrash = true
    }

    func hideTrash() {
        isShowingTrash = false
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
        objectWillChange.send()
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
            
            let allResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
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
                    blurScore: nil,
                    exposureIsBad: false,
                    isBlurredOrShaky: false,
                    isDocumentLike: false,
                    isLargeFile: fileSize > 10 * 1024 * 1024,
                    similarGroupId: nil,
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
        // This can be a long-running task, so it's good to keep it off the main thread.
        // The analysis logic itself is not included here for brevity.
        isAnalyzing = true
        analysisProgress = 0
        // Simulate analysis
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isAnalyzing = false
            self.analysisProgress = 1.0
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
        objectWillChange.send()
    }

    func markCurrentForDeletion() {
        guard let currentItem = currentItem else { return }
        if let index = items.firstIndex(where: { $0.id == currentItem.id }) {
            items[index].markedForDeletion = true
            objectWillChange.send()
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
            objectWillChange.send()
            refreshSession() // Refresh if needed
        }
    }

    func setDeletion(_ item: PhotoItem, to flag: Bool) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion = flag
            objectWillChange.send()
            refreshSession()
        }
    }

    func removeFromPending(_ item: PhotoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].markedForDeletion = false
            objectWillChange.send()
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
