import Foundation

enum CacheMissSource {
    case memory
    case disk
}

actor CacheCoordinator {
    private let memoryPool = MemoryPool()
    private let diskVault: DiskVault

    init(database: PhotoStoreDatabase) {
        self.diskVault = DiskVault(database: database)
    }

    func bootstrap(with assets: [PhotoAssetMetadata]) async {
        await diskVault.bootstrapIfNeeded(with: assets)
    }

    func hydrate(_ assets: [PhotoAssetMetadata], tag: CacheTag) async {
        await memoryPool.store(assets, tag: tag)
        let thumbnails = assets.map { asset in
            PhotoThumbnailDescriptor(assetId: asset.id, palette: asset.palette, source: .memory)
        }
        await diskVault.store(thumbnails: thumbnails)
    }

    func metadata(for ids: [String]) async -> [PhotoAssetMetadata] {
        let memoryHits = await memoryPool.metadata(for: ids)
        guard memoryHits.count < ids.count else { return memoryHits }
        let missingIds = Set(ids).subtracting(memoryHits.map { $0.id })
        let diskHits = await diskVault.metadata(for: Array(missingIds))
        return memoryHits + diskHits
    }

    func thumbnails(for ids: [String]) async -> [PhotoThumbnailDescriptor] {
        let memoryHits = await memoryPool.thumbnails(for: ids)
        guard memoryHits.count < ids.count else { return memoryHits }
        let missingIds = Set(ids).subtracting(memoryHits.map { $0.assetId })
        let diskHits = await diskVault.thumbnails(for: Array(missingIds))
        return memoryHits + diskHits
    }

    func release(tag: CacheTag) async {
        await memoryPool.release(tag: tag)
    }
}
