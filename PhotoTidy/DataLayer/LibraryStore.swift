import Foundation
import Photos

/// 统一的全库数据流，按 Scope 分页加载并输出增量事件
actor LibraryStore {
    enum Event {
        case switching(scope: PhotoQuery, generation: UUID)
        case initialReady(generation: UUID, items: [PhotoItem])
        case append(generation: UUID, items: [PhotoItem])
        case finished(generation: UUID)
    }

    private let analysisCache: PhotoAnalysisCacheStore
    private let photoRepository: PhotoRepository
    private var generation = UUID()
    private var currentScope: PhotoQuery = .all
    private var pageSize: Int = 200
    private var continuation: AsyncStream<Event>.Continuation?
    private var paginationTask: Task<Void, Never>?

    init(
        analysisCache: PhotoAnalysisCacheStore,
        photoRepository: PhotoRepository
    ) {
        self.analysisCache = analysisCache
        self.photoRepository = photoRepository
    }

    func start(scope: PhotoQuery = .all, pageSize: Int = 200) -> AsyncStream<Event> {
        paginationTask?.cancel()
        continuation?.finish()
        generation = UUID()
        currentScope = scope
        self.pageSize = pageSize
        let currentGeneration = generation

        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(.switching(scope: scope, generation: currentGeneration))
            Task { await self.streamInitialBatch(generation: currentGeneration) }
        }
    }

    func refresh() -> AsyncStream<Event> {
        start(scope: currentScope, pageSize: pageSize)
    }

    private func streamInitialBatch(generation: UUID) async {
        guard generation == self.generation else {
            continuation?.finish()
            return
        }
        await photoRepository.resetPaging(for: currentScope)
        await photoRepository.bootstrapLibraryIfNeeded()
        let cache = analysisCache.snapshot()
        let first = await photoRepository.fetchNextBatch(query: currentScope, batchSize: pageSize)
        guard generation == self.generation else {
            continuation?.finish()
            return
        }
        let initialItems = PhotoItemBuilder.makeItems(from: first, cache: cache)
        continuation?.yield(.initialReady(generation: generation, items: initialItems))
        scheduleBackgroundPagination(generation: generation, cache: cache)
    }

    private func scheduleBackgroundPagination(
        generation: UUID,
        cache: [String: PhotoAnalysisCacheEntry]
    ) {
        paginationTask?.cancel()
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await self.runPagination(generation: generation, cache: cache)
        }
    }

    private func runPagination(
        generation: UUID,
        cache: [String: PhotoAnalysisCacheEntry]
    ) async {
        while await isCurrentGeneration(generation) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            let hasMore = await loadNextBatch(generation: generation, cache: cache)
            if !hasMore { break }
        }
        if await isCurrentGeneration(generation) {
            continuation?.yield(.finished(generation: generation))
            continuation?.finish()
        }
    }

    private func loadNextBatch(
        generation: UUID,
        cache: [String: PhotoAnalysisCacheEntry]
    ) async -> Bool {
        guard await isCurrentGeneration(generation) else { return false }
        let batch = await photoRepository.fetchNextBatch(query: currentScope, batchSize: pageSize)
        guard await isCurrentGeneration(generation) else { return false }
        guard !batch.isEmpty else { return false }
        let items = PhotoItemBuilder.makeItems(from: batch, cache: cache)
        continuation?.yield(.append(generation: generation, items: items))
        return batch.count == pageSize
    }

    private func isCurrentGeneration(_ id: UUID) async -> Bool {
        generation == id
    }
}
