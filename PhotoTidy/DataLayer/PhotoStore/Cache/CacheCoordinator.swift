import Foundation
import CoreGraphics

enum CacheMissSource {
    case memory
    case disk
}

actor CacheCoordinator {
    private let memoryPool = MemoryPool()
    private let diskVault: DiskVault
    private let thumbnailBridge = ThumbnailBridge()

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

    func thumbnailData(for asset: PhotoAssetMetadata, targetSize: CGSize) async -> Data? {
        if let cached = await memoryPool.thumbnailData(for: asset.id) {
            return cached
        }
        if let disk = await diskVault.thumbnailData(for: asset.id) {
            await memoryPool.store(thumbnailData: disk, for: asset.id)
            return disk
        }
        guard let generated = await thumbnailBridge.makeThumbnail(for: asset, targetSize: targetSize) else {
            return nil
        }
        await memoryPool.store(thumbnailData: generated, for: asset.id)
        await diskVault.store(thumbnailData: generated, for: asset.id)
        return generated
    }

    func warmThumbnails(for assets: [PhotoAssetMetadata], targetSize: CGSize) async {
        guard !assets.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for asset in assets {
                group.addTask {
                    _ = await self.thumbnailData(for: asset, targetSize: targetSize)
                }
            }
        }
    }

    func release(tag: CacheTag) async {
        await memoryPool.release(tag: tag)
    }

    func clearAll() async {
        await memoryPool.clear()
        await diskVault.clear()
    }
}
