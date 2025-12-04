import Foundation

actor MemoryPool {
    private var metadataCache: [String: PhotoAssetMetadata] = [:]
    private var thumbnailCache: [String: PhotoThumbnailDescriptor] = [:]
    private var tagBindings: [CacheTag: Set<String>] = [:]

    func store(_ assets: [PhotoAssetMetadata], tag: CacheTag) {
        var identifiers = tagBindings[tag] ?? Set<String>()
        for asset in assets {
            metadataCache[asset.id] = asset
            if thumbnailCache[asset.id] == nil {
                thumbnailCache[asset.id] = PhotoThumbnailDescriptor(
                    assetId: asset.id,
                    palette: asset.palette,
                    source: .memory
                )
            }
            identifiers.insert(asset.id)
        }
        tagBindings[tag] = identifiers
    }

    func metadata(for ids: [String]) -> [PhotoAssetMetadata] {
        ids.compactMap { metadataCache[$0] }
    }

    func thumbnails(for ids: [String]) -> [PhotoThumbnailDescriptor] {
        ids.compactMap { thumbnailCache[$0] }
    }

    func release(tag: CacheTag) {
        guard let identifiers = tagBindings[tag] else { return }
        for identifier in identifiers {
            metadataCache.removeValue(forKey: identifier)
            thumbnailCache.removeValue(forKey: identifier)
        }
        tagBindings.removeValue(forKey: tag)
    }
}
