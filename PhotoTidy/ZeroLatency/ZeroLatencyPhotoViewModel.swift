import Foundation
import Combine
import Photos
import SwiftUI

@MainActor
final class ZeroLatencyPhotoViewModel: ObservableObject {
    @Published var dashboardSnapshot: DashboardSnapshot = .placeholder()
    @Published var gridItems: [AssetItem] = []
    @Published var analysisState: AnalysisState = .idle
    @Published var authorizationStatus: PHAuthorizationStatus

    let imageCache = ImageCache()

    private let cacheStore = ZeroLatencyCacheStore()
    private lazy var photoLoader = PhotoLoader(imageCache: imageCache)
    private lazy var analysisManager = AnalysisManager(cacheStore: cacheStore)
    private let permissionsManager = PermissionsManager()
    private let libraryObserver = PhotoLibraryObserver()

    private var cancellables: Set<AnyCancellable> = []
    private var snapshotObserver: NSObjectProtocol?
    private var hasSeededRecentPreview = false

    init() {
        authorizationStatus = permissionsManager.status
        photoLoader.delegate = self
        setupBindings()
        observeCache()
        Task {
            await loadInitialSnapshot()
        }
    }

    deinit {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let snapshotObserver = self.snapshotObserver {
                NotificationCenter.default.removeObserver(snapshotObserver)
            }
            self.libraryObserver.stopObserving()
            self.photoLoader.stop()
        }
    }

    func requestAuthorization() {
        permissionsManager.requestAuthorization()
    }

    func onAppear() {
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            photoLoader.start()
        }
    }

    func thumbnailDidAppear(at index: Int) {
        photoLoader.ensurePagingBuffer(forDisplayedIndex: index)
    }

    func reportVisibleRange(_ range: Range<Int>) {
        photoLoader.visibleRangeDidChange(range)
    }

    func refreshPermissions() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func triggerAnalysisForSimilarFeature() {
        Task {
            await analysisManager.enqueue(assets: gridItems.map { $0.asset })
        }
    }

    private func setupBindings() {
        permissionsManager.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.authorizationStatus = status
                if status == .authorized || status == .limited {
                    self.photoLoader.start()
                }
            }
            .store(in: &cancellables)

        photoLoader.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                guard let self else { return }
                self.gridItems = items
                self.seedRecentPreviewIfNeeded(with: items)
            }
            .store(in: &cancellables)

        analysisManager.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.analysisState = state
            }
        }
    }

    private func observeCache() {
        snapshotObserver = NotificationCenter.default.addObserver(
            forName: .photoAnalysisCacheDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let snapshot = notification.userInfo?["snapshot"] as? DashboardSnapshot else { return }
            self?.dashboardSnapshot = snapshot
        }
    }

    private func loadInitialSnapshot() async {
        let snapshot = await cacheStore.currentSnapshot()
        await MainActor.run {
            dashboardSnapshot = snapshot
        }
    }

    private func seedRecentPreviewIfNeeded(with items: [AssetItem]) {
        guard !hasSeededRecentPreview, !items.isEmpty else { return }
        hasSeededRecentPreview = true
        let previews = items.prefix(24).map {
            RecentPreviewItem(id: $0.id, thumb: nil, createdAt: $0.creationDate)
        }
        Task {
            await cacheStore.updateDashboard(recentPreview: previews)
        }
    }

    private func handleLibraryChange() {
        hasSeededRecentPreview = false
        photoLoader.reloadLibrary()
    }

    nonisolated private static func collectStats(from fetchResult: PHFetchResult<PHAsset>, previewLimit: Int = 24) -> (Int, [MonthlyCount], [RecentPreviewItem]) {
        let total = fetchResult.count
        var monthlyDictionary: [String: (Int, Int, Int)] = [:]
        var previews: [RecentPreviewItem] = []
        let calendar = Calendar.current

        fetchResult.enumerateObjects { asset, index, stop in
            let date = asset.creationDate ?? asset.modificationDate ?? Date()
            let comps = calendar.dateComponents([.year, .month], from: date)
            if let year = comps.year, let month = comps.month {
                let key = "\(year)-\(month)"
                let existing = monthlyDictionary[key] ?? (year, month, 0)
                monthlyDictionary[key] = (year, month, existing.2 + 1)
            }
            if index < previewLimit {
                previews.append(RecentPreviewItem(id: asset.localIdentifier, thumb: nil, createdAt: date))
            }
        }

        let monthly = monthlyDictionary.values
            .map { MonthlyCount(year: $0.0, month: $0.1, count: $0.2) }
            .sorted { lhs, rhs in
                if lhs.year == rhs.year {
                    return lhs.month > rhs.month
                }
                return lhs.year > rhs.year
            }

        return (total, monthly, previews)
    }
}

extension ZeroLatencyPhotoViewModel: PhotoLoaderDelegate {
    func photoLoader(_ loader: PhotoLoader, didUpdateFetchResult fetchResult: PHFetchResult<PHAsset>) {
        libraryObserver.startObserving(fetchResult: fetchResult)
        libraryObserver.onChange = { [weak self] _ in
            Task { @MainActor in
                self?.handleLibraryChange()
            }
        }
        Task.detached(priority: .utility) { [weak self] in
            let stats = ZeroLatencyPhotoViewModel.collectStats(from: fetchResult)
            await self?.cacheStore.updateDashboard(
                totalCount: stats.0,
                monthlyCounts: stats.1,
                recentPreview: stats.2,
                topLargeFiles: nil
            )
        }
    }

    func photoLoader(_ loader: PhotoLoader, didLoadAssets assets: [PHAsset]) {
        Task {
            await analysisManager.enqueue(assets: assets)
        }
    }
}
