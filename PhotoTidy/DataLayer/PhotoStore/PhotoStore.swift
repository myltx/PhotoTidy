import Foundation

actor PhotoStore {
    private let database: PhotoStoreDatabase
    private let cacheCoordinator: CacheCoordinator
    private let prefetchManager = PrefetchManager()
    private let analysisScheduler = AnalysisScheduler()
    private let catalog: IndexCatalog
    private var analysisWorker: AnalysisWorker?
    private var feedStates: [PhotoQueryIntent: PhotoFeedState] = [:]
    private var datasetCache: [PhotoQueryIntent: [PhotoFeedItem]] = [:]

    init(seedCount: Int = 480, database: PhotoStoreDatabase = PhotoStoreDatabase()) {
        self.database = database
        self.cacheCoordinator = CacheCoordinator(database: database)
        let photoLibraryAssets = PhotoLibraryBootstrapper().loadAssets(limit: seedCount)
        let assets: [PhotoAssetMetadata]
        if photoLibraryAssets.isEmpty {
            assets = MockAssetProvider().makeAssets(count: seedCount)
        } else {
            assets = photoLibraryAssets
        }
        database.bootstrapIfNeeded(with: assets)
        catalog = IndexCatalog(database: database)
        let worker = AnalysisWorker(
            scheduler: analysisScheduler,
            database: database
        ) { [weak self] in
            guard let self else { return }
            Task { await self.handleAnalysisUpdates() }
        }
        Task {
            await cacheCoordinator.bootstrap(with: assets)
        }
        analysisWorker = worker
        Task { await worker.start() }
    }

    func ensureFeed(intent: PhotoQueryIntent) async -> PhotoFeedState {
        if let existing = feedStates[intent], existing.status != .idle {
            return existing
        }
        return await loadInitial(intent: intent)
    }

    func requestNextPage(intent: PhotoQueryIntent) async -> PhotoFeedState {
        guard var state = feedStates[intent] else {
            return await loadInitial(intent: intent)
        }
        guard let cursor = state.cursor else { return state }
        let dataset = dataset(for: intent)
        let page = paginate(dataset: dataset, cursor: cursor, pageSize: intent.pageSize)
        state.items.append(contentsOf: page.items)
        state.cursor = page.cursor
        state.status = page.status
        feedStates[intent] = state
        await prefetchManager.prefetch(
            intent: intent,
            assets: assets(from: page.items),
            coordinator: cacheCoordinator
        )
        return state
    }

    func dashboardSnapshot() -> DashboardSnapshot {
        catalog.dashboard()
    }

    func timelineBuckets() -> [TimelineBucketSnapshot] {
        catalog.buckets()
    }

    func availableMonths() -> [PhotoAssetMetadata.MonthKey] {
        catalog.monthKeys()
    }

    func prefetchLog() async -> [PhotoStoreEventLog] {
        await prefetchManager.currentLog()
    }

    private func loadInitial(intent: PhotoQueryIntent) async -> PhotoFeedState {
        var state = PhotoFeedState(intent: intent, items: [], cursor: nil, status: .loading)
        feedStates[intent] = state
        let dataset = dataset(for: intent)
        let page = paginate(dataset: dataset, cursor: nil, pageSize: intent.pageSize)
        state.items = page.items
        state.cursor = page.cursor
        state.status = page.status
        feedStates[intent] = state
        await prefetchManager.prefetch(
            intent: intent,
            assets: assets(from: page.items),
            coordinator: cacheCoordinator
        )
        await scheduleAnalysisIfNeeded(for: dataset, intent: intent)
        return state
    }

    private func dataset(for intent: PhotoQueryIntent) -> [PhotoFeedItem] {
        if let cached = datasetCache[intent] {
            return cached
        }
        let dataset: [PhotoFeedItem]
        switch intent {
        case .sequential(let scope):
            let assets = catalog.sequential(scope: scope)
            dataset = assets.map { makeAssetItem(from: $0) }
        case .grouped(let kind):
            let groups = catalog.groups(kind: kind)
            dataset = groups.map { group in
                let cover = group.cover ?? group.members.first
                let palette = cover?.palette ?? ThumbnailPalette(startHex: "#222", endHex: "#444")
                let thumbnail = PhotoThumbnailDescriptor(assetId: group.id, palette: palette, source: .disk)
                return PhotoFeedItem(id: group.id, payload: .group(group), thumbnail: thumbnail)
            }
        case .ranked(let kind):
            let assets = catalog.ranked(kind: kind)
            dataset = assets.map { makeAssetItem(from: $0) }
        case .pending(let kind):
            let assets = catalog.pending(kind: kind)
            dataset = assets.map { makeAssetItem(from: $0) }
        case .bucketed:
            let buckets = catalog.buckets()
            dataset = buckets.map { bucket in
                let palette = bucket.cover?.palette ?? ThumbnailPalette(startHex: "#1D1D1D", endHex: "#3A3A3A")
                let descriptor = PhotoThumbnailDescriptor(assetId: bucket.id, palette: palette, source: .disk)
                return PhotoFeedItem(id: bucket.id, payload: .bucket(bucket), thumbnail: descriptor)
            }
        case .dashboard:
            dataset = []
        }
        datasetCache[intent] = dataset
        return dataset
    }

    private func paginate(
        dataset: [PhotoFeedItem],
        cursor: PhotoFeedCursor?,
        pageSize: Int
    ) -> (items: [PhotoFeedItem], cursor: PhotoFeedCursor?, status: PhotoFeedState.Status) {
        guard pageSize > 0 else {
            return (dataset, nil, .exhausted)
        }
        let startIndex = cursor?.offset ?? 0
        guard startIndex < dataset.count else {
            return ([], nil, .exhausted)
        }
        let endIndex = min(startIndex + pageSize, dataset.count)
        let slice = Array(dataset[startIndex..<endIndex])
        let nextCursor = endIndex < dataset.count ? PhotoFeedCursor(offset: endIndex, context: cursor?.context) : nil
        let status: PhotoFeedState.Status = nextCursor == nil ? .exhausted : .streaming
        return (slice, nextCursor, status)
    }

    private func makeAssetItem(from asset: PhotoAssetMetadata) -> PhotoFeedItem {
        let thumbnail = PhotoThumbnailDescriptor(assetId: asset.id, palette: asset.palette, source: .memory)
        return PhotoFeedItem(id: asset.id, payload: .asset(asset), thumbnail: thumbnail)
    }

    private func assets(from items: [PhotoFeedItem]) -> [PhotoAssetMetadata] {
        items.compactMap { item in
            switch item.payload {
            case .asset(let asset):
                return asset
            case .group(let group):
                return group.cover
            case .bucket(let bucket):
                return bucket.cover
            }
        }
    }

    private func scheduleAnalysisIfNeeded(for dataset: [PhotoFeedItem], intent: PhotoQueryIntent) async {
        let assetIds = dataset.compactMap { item -> String? in
            switch item.payload {
            case .asset(let asset):
                return asset.id
            case .group(let group):
                return group.cover?.id
            case .bucket:
                return nil
            }
        }
        switch intent {
        case .ranked(let kind):
            let taskKind: AnalysisTaskKind = (kind == .blurred) ? .blur : .document
            await analysisScheduler.schedule(kind: taskKind, assetIds: assetIds)
        case .grouped(let kind) where kind == .similar:
            await analysisScheduler.schedule(kind: .similarity, assetIds: assetIds)
        case .sequential:
            await analysisScheduler.schedule(kind: .metadata, assetIds: assetIds)
        default:
            break
        }
    }

    private func handleAnalysisUpdates() async {
        datasetCache.removeAll()
        for (intent, var state) in feedStates {
            state.status = .idle
            feedStates[intent] = state
        }
    }
}
