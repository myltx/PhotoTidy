import Foundation
import Combine
import SwiftUI
import Photos

@MainActor
final class PhotoCleanupViewModel: ObservableObject {
    struct SmartCleanupResumeInfo {
        let pendingDeletionCount: Int
        let anchorAsset: PhotoAssetMetadata?
    }

    enum DashboardDetail {
        case similar
        case blurry
        case screenshots
        case largeFiles
    }

    enum SmartThumbnailTarget {
        case dashboardCard
        case tinderCard
    }

    enum CleanerFilter {
        case all
    }

    @Published var deviceStorageUsage: DeviceStorageUsage = DeviceStorageUsage(totalBytes: 0, usedBytes: 0, freeBytes: 0, clearableBytes: 0)
    @Published var pendingDeletionItems: [PhotoAssetMetadata] = []
    @Published var skippedItems: [PhotoAssetMetadata] = []
    @Published var smartCleanupResumeInfo: SmartCleanupResumeInfo?
    @Published var isLoading: Bool = true
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var settingsNavigationPath = NavigationPath()
    @Published var selectedTheme: AppTheme = PhotoCleanupViewModel.loadStoredTheme() {
        didSet {
            PhotoCleanupViewModel.storeTheme(selectedTheme)
        }
    }
    @Published var isShowingCleaner: Bool = false

    var pendingDeletionTotalSize: Int {
        pendingDeletionItems.reduce(0) { $0 + $1.byteSize }
    }

    private let facade: PhotoStoreFacade
    private var cancellables: Set<AnyCancellable> = []
    private let sequentialIntent: PhotoQueryIntent = .sequential(scope: .all)
    private let pendingIntent: PhotoQueryIntent = .pending(kind: .pendingDeletion)
    private let skippedIntent: PhotoQueryIntent = .pending(kind: .skipped)
    private var sequentialAssets: [PhotoAssetMetadata] = []
    private var preloadedIntents: Set<PhotoQueryIntent> = []

    init(facade: PhotoStoreFacade = .shared) {
        self.facade = facade
        observeFacade()
        bootstrapFeeds()
    }

    func showDetail(_ detail: DashboardDetail) {
        // TODO: Hook up navigation to legacy detail flows.
    }

    func showCleaner(filter: CleanerFilter) {
        isShowingCleaner = true
    }

    func preloadSampleThumbnails(for detail: DashboardDetail, target: SmartThumbnailTarget) {
        guard let intent = queryIntent(for: detail),
              !preloadedIntents.contains(intent) else { return }
        preloadedIntents.insert(intent)
        _ = facade.feedState(for: intent)
        facade.requestNextPage(intent: intent)
    }

    func resumeSmartCleanup() {
        showCleaner(filter: .all)
    }

    func resetSmartCleanupProgressOnly() {
        smartCleanupResumeInfo = nil
    }

    func clearPendingDeletionCache() {
        let ids = pendingDeletionItems.map(\.id)
        applyDecision(assetIds: ids, newState: .clean)
    }

    func resetCleanupProgress() {
        settingsNavigationPath = NavigationPath()
        facade.clearAllCaches()
    }

    func removeAssetFromPending(id: String) {
        applyDecision(assetIds: [id], newState: .clean)
    }

    func confirmPendingDeletion(ids: [String]? = nil) {
        let targetIds = ids ?? pendingDeletionItems.map(\.id)
        guard !targetIds.isEmpty else { return }
        facade.removeAssets(assetIds: targetIds)
    }

    func confirmDeletionForSkipped(ids: [String]) {
        applyDecision(assetIds: ids, newState: .pendingDeletion)
    }

    func reinstateSkippedPhotos(ids: [String]) {
        applyDecision(assetIds: ids, newState: .clean)
    }

    func acknowledgeSkippedPhotos(ids: [String]) {
        applyDecision(assetIds: ids, newState: .clean)
    }

    func clearSkippedRecords() {
        let ids = skippedItems.map(\.id)
        acknowledgeSkippedPhotos(ids: ids)
    }

    func dismissCleaner() {
        isShowingCleaner = false
    }
}

// MARK: - Private helpers
private extension PhotoCleanupViewModel {
    func observeFacade() {
        facade.$dashboard
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.deviceStorageUsage = snapshot.storageUsage
            }
            .store(in: &cancellables)

        facade.$feeds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] feeds in
                guard let self else { return }
                if let sequential = feeds[self.sequentialIntent] {
                    self.handleSequentialFeed(sequential)
                }
                if let pending = feeds[self.pendingIntent] {
                    self.handlePendingFeed(pending)
                }
                if let skipped = feeds[self.skippedIntent] {
                    self.handleSkippedFeed(skipped)
                }
            }
            .store(in: &cancellables)
    }

    func bootstrapFeeds() {
        handleSequentialFeed(facade.feedState(for: sequentialIntent))
        handlePendingFeed(facade.feedState(for: pendingIntent))
        handleSkippedFeed(facade.feedState(for: skippedIntent))
    }

    func handleSequentialFeed(_ state: PhotoFeedState) {
        sequentialAssets = state.items.compactMap { item in
            if case let .asset(asset) = item.payload {
                return asset
            }
            return nil
        }
        updateResumeInfo()
        isLoading = state.status == .loading
    }

    func handlePendingFeed(_ state: PhotoFeedState) {
        pendingDeletionItems = state.items.compactMap { item in
            if case let .asset(asset) = item.payload {
                return asset
            }
            return nil
        }
        updateResumeInfo()
    }

    func handleSkippedFeed(_ state: PhotoFeedState) {
        skippedItems = state.items.compactMap { item in
            if case let .asset(asset) = item.payload {
                return asset
            }
            return nil
        }
    }

    func updateResumeInfo() {
        guard !pendingDeletionItems.isEmpty else {
            smartCleanupResumeInfo = nil
            return
        }
        smartCleanupResumeInfo = SmartCleanupResumeInfo(
            pendingDeletionCount: pendingDeletionItems.count,
            anchorAsset: sequentialAssets.first
        )
    }

    func queryIntent(for detail: DashboardDetail) -> PhotoQueryIntent? {
        switch detail {
        case .similar:
            return .grouped(kind: .similar)
        case .blurry:
            return .ranked(kind: .blurred)
        case .screenshots:
            return .ranked(kind: .screenshots)
        case .largeFiles:
            return .ranked(kind: .largeFiles)
        }
    }

    private static let themeDefaultsKey = "settings.selectedTheme"

    private static func loadStoredTheme() -> AppTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: themeDefaultsKey),
              let theme = AppTheme(rawValue: rawValue) else {
            return .system
        }
        return theme
    }

    private static func storeTheme(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: themeDefaultsKey)
    }

    func applyDecision(assetIds: [String], newState: PhotoDecisionState) {
        guard !assetIds.isEmpty else { return }
        facade.applyDecision(assetIds: assetIds, newState: newState)
    }
}
