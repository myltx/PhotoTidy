
import Foundation
import Photos

protocol PhotoSessionManagerDelegate: AnyObject {
    func photoSessionManager(_ manager: PhotoSessionManager, didUpdate session: PhotoSession)
}

final class PhotoSessionManager {
    private let photoRepository: PhotoRepository
    private let analysisCache: PhotoAnalysisCacheStore
    private let thumbnailStore: ThumbnailStore
    private var sessions: [UUID: PhotoSession] = [:]
    weak var delegate: PhotoSessionManagerDelegate?

    init(
        photoRepository: PhotoRepository = PhotoRepository(),
        analysisCache: PhotoAnalysisCacheStore = PhotoAnalysisCacheStore(),
        thumbnailStore: ThumbnailStore = ThumbnailStore()
    ) {
        self.photoRepository = photoRepository
        self.analysisCache = analysisCache
        self.thumbnailStore = thumbnailStore
    }

    func session(scope: PhotoSessionScope) -> PhotoSession {
        if let existing = sessions.values.first(where: { $0.scope == scope }) {
            return existing
        }
        let session = PhotoSession(
            scope: scope,
            batchSize: batchSize(for: scope),
            windowLimit: windowLimit(for: scope)
        )
        session.delegate = self
        sessions[session.id] = session
        return session
    }

    func loadNextBatch(for session: PhotoSession) async {
        guard !session.state.isExhausted else { return }
        let offset = session.state.nextOffset
        let descriptors = await loadDescriptors(scope: session.scope, offset: offset, limit: session.batchSize)
        guard !descriptors.isEmpty else {
            session.markExhausted()
            return
        }
        let cacheSnapshot = analysisCache.snapshot()
        var newItems: [PhotoItem] = []
        for descriptor in descriptors {
            let asset = descriptor.asset
            let estimatedSize = descriptor.byteSize
            var item = PhotoItemFactory.makePhotoItem(for: asset, estimatedSize: estimatedSize)
            if let entry = cacheSnapshot[item.id], entry.fileSize == item.fileSize {
                PhotoItemFactory.applyCachedEntry(entry, to: &item)
            }
            newItems.append(item)
        }
        if case let .filter(filterMode) = session.scope {
            newItems = newItems.filter { matches($0, filter: filterMode) }
            if newItems.isEmpty {
                await loadNextBatch(for: session)
                return
            }
        }
        session.append(items: newItems)
        await preloadThumbnails(for: newItems)
    }

    func resetSessions() {
        sessions.removeAll()
    }

    private func windowLimit(for scope: PhotoSessionScope) -> Int? {
        guard FeatureToggles.enableApplePhotosArchitecture else { return nil }
        switch scope {
        case .all, .filter:
            return 60
        case .month, .album:
            return 120
        }
    }

    private func batchSize(for scope: PhotoSessionScope) -> Int {
        switch scope {
        case .all, .filter:
            return 10
        case .month, .album:
            return 18
        }
    }

    private func loadDescriptors(scope: PhotoSessionScope, offset: Int, limit: Int) async -> [AssetDescriptor] {
        switch scope {
        case .all:
            return await photoRepository.fetchNextBatch(query: .all, batchSize: limit)
        case .month(let year, let month):
            let descriptors = await photoRepository.prefetchMonth(year, month: month, limit: offset + limit)
            let start = min(offset, descriptors.count)
            let slice = descriptors[start..<descriptors.count]
            return Array(slice.prefix(limit))
        case .filter:
            return await photoRepository.fetchNextBatch(query: .all, batchSize: limit)
        case .album(let identifier):
            let query = PhotoQuery(scope: .album(identifier: identifier))
            return await photoRepository.fetchNextBatch(query: query, batchSize: limit)
        }
    }

    private func preloadThumbnails(for items: [PhotoItem]) async {
        guard !items.isEmpty else { return }
        await thumbnailStore.preload(assetIds: items.map { $0.id }, target: .tinderCard)
    }

    private func matches(_ item: PhotoItem, filter: CleanupFilterMode) -> Bool {
        switch filter {
        case .all:
            return true
        case .similar:
            return item.similarGroupId != nil
        case .blurred:
            return item.isBlurredOrShaky
        case .screenshots:
            return item.isScreenshot || item.isDocumentLike
        case .documents:
            return item.isDocumentLike
        case .large:
            return item.isLargeFile
        }
    }
}

extension PhotoSessionManager: PhotoSessionDelegate {
    func photoSession(_ session: PhotoSession, didUpdate state: PhotoSessionState) {
        delegate?.photoSessionManager(self, didUpdate: session)
    }
}
