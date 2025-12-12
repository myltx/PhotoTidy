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

    private lazy var photoLoader = PhotoLoader(imageCache: imageCache)
    private let permissionsManager = PermissionsManager()
    private let libraryObserver = PhotoLibraryObserver()
    private let analysisCache: PhotoAnalysisRepository
    private let userStateRepo: PhotoUserStateRepository
    private let metaStore: AnalysisDashboardMetaStore
    private let dataController: PhotoDataController

    private var cancellables: Set<AnyCancellable> = []
    private var totalAssetCount: Int = 0
    private var lastDashboardUpdatedAt: Date = .distantPast
    private var lastSimilarityRun: Date?
    private var needsBootstrapFlag: Bool = true
    private var wasAnalyzing = false

    init() {
        let container = PhotoDataContainer.shared
        self.analysisCache = container.analysisRepository
        self.userStateRepo = container.userStateRepository
        self.metaStore = container.dashboardMetaStore
        self.dataController = container.dataController
        authorizationStatus = permissionsManager.status
        photoLoader.delegate = self
        needsBootstrapFlag = analysisCache.snapshot().isEmpty
        setupBindings()
        Task { [weak self] in
            guard let self else { return }
            let meta = await self.metaStore.load()
            self.lastDashboardUpdatedAt = meta.lastUpdated
            self.lastSimilarityRun = meta.lastSimilarityRun
            self.rebuildDashboardSnapshot(using: self.dataController.currentSnapshot())
        }
    }

    deinit {
        scheduleTeardown()
    }

    // Swift 6 中 deinit 默认非隔离，避免直接访问 MainActor 属性。
    nonisolated private func scheduleTeardown() {
        Task { @MainActor [weak self] in
            guard let self else { return }
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
        let candidates = dataController.currentSnapshot().items
        dataController.elevateAnalysisPriority(for: candidates)
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
                self.rebuildDashboardSnapshot(using: self.dataController.currentSnapshot())
            }
            .store(in: &cancellables)

        let previousSnapshotHandler = dataController.onSnapshotChange
        dataController.onSnapshotChange = { [weak self] snapshot in
            previousSnapshotHandler?(snapshot)
            self?.rebuildDashboardSnapshot(using: snapshot)
        }

        let previousStateHandler = dataController.onAnalysisStateChange
        dataController.onAnalysisStateChange = { [weak self] state in
            previousStateHandler?(state)
            guard let self else { return }
            self.analysisState = state
            switch state {
            case .analyzing:
                self.wasAnalyzing = true
            case .idle:
                if self.wasAnalyzing {
                    self.wasAnalyzing = false
                    Task { [weak self] in
                        guard let self else { return }
                        let meta = await self.metaStore.load()
                        self.lastDashboardUpdatedAt = meta.lastUpdated
                        self.lastSimilarityRun = meta.lastSimilarityRun
                        self.rebuildDashboardSnapshot(using: self.dataController.currentSnapshot())
                    }
                }
            }
        }
    }

    private func rebuildDashboardSnapshot(using snapshot: PhotoDataController.Snapshot) {
        if needsBootstrapFlag,
           snapshot.items.contains(where: { $0.blurScore != nil || $0.pHash != nil }) {
            needsBootstrapFlag = false
        }

        let totalFromMonths = snapshot.monthAssetTotals.values.reduce(0, +)
        let total = totalAssetCount > 0 ? totalAssetCount : (totalFromMonths > 0 ? totalFromMonths : snapshot.items.count)

        let monthlyCounts: [MonthlyCount] = snapshot.monthAssetTotals.compactMap { key, count in
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]) else { return nil }
            return MonthlyCount(year: year, month: month, count: count)
        }
        .sorted { lhs, rhs in
            if lhs.year == rhs.year { return lhs.month > rhs.month }
            return lhs.year > rhs.year
        }

        let recentPreview: [RecentPreviewItem] = snapshot.items.prefix(24).map {
            RecentPreviewItem(id: $0.id, thumb: nil, createdAt: $0.creationDate ?? Date())
        }

        let topLargeFiles: [String] = snapshot.items
            .sorted { $0.fileSize > $1.fileSize }
            .prefix(20)
            .map(\.id)

        let lastUpdated = lastDashboardUpdatedAt
        let meta = AnalysisMeta(lastSimilarityRun: lastSimilarityRun, version: "1.0.0")

        dashboardSnapshot = DashboardSnapshot(
            schemaVersion: 1,
            totalCount: total,
            recentPreview: recentPreview,
            monthlyCounts: monthlyCounts,
            topLargeFiles: topLargeFiles,
            analysisMeta: meta,
            lastUpdated: lastUpdated,
            needsBootstrap: needsBootstrapFlag
        )
    }
}

extension ZeroLatencyPhotoViewModel: PhotoLoaderDelegate {
    func photoLoader(_ loader: PhotoLoader, didUpdateFetchResult fetchResult: PHFetchResult<PHAsset>) {
        libraryObserver.startObserving(fetchResult: fetchResult)
        totalAssetCount = fetchResult.count

        libraryObserver.onChange = { [weak self] details in
            guard let self else { return }
            Task { @MainActor in
                guard details.hasIncrementalChanges, !self.gridItems.isEmpty else {
                    self.dataController.resetPagingState()
                    self.photoLoader.reloadLibrary()
                    return
                }
                self.photoLoader.applyChangeDetails(details)
                self.dataController.applyLibraryChange(details)
            }
        }

        dataController.handleFetchResultUpdate(fetchResult)
        rebuildDashboardSnapshot(using: dataController.currentSnapshot())
    }

    func photoLoader(_ loader: PhotoLoader, didLoadAssets assets: [PHAsset]) {
        dataController.handleLoadedAssets(assets)
    }
}
