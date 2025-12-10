import Foundation
import Photos

/// 负责将 AssetDescriptor + 分析缓存转换成 PhotoItem
struct PhotoItemBuilder {
    static func makeItems(
        from descriptors: [AssetDescriptor],
        cache: [String: PhotoAnalysisCacheEntry]
    ) -> [PhotoItem] {
        guard !descriptors.isEmpty else { return [] }
        var results: [PhotoItem] = []
        results.reserveCapacity(descriptors.count)

        for descriptor in descriptors {
            let asset = descriptor.asset
            var item = PhotoItem(
                id: descriptor.id,
                asset: asset,
                pixelSize: CGSize(width: descriptor.pixelWidth, height: descriptor.pixelHeight),
                fileSize: descriptor.byteSize,
                creationDate: descriptor.creationDate,
                isVideo: asset.mediaType == .video,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                pHash: nil,
                blurScore: nil,
                exposureIsBad: false,
                isBlurredOrShaky: false,
                isDocumentLike: false,
                isTextImage: false,
                isLargeFile: descriptor.byteSize > 15 * 1_024 * 1_024,
                similarGroupId: nil,
                similarityKind: nil,
                assetType: nil,
                markedForDeletion: false
            )
            if let entry = cache[item.id],
               entry.version == PhotoAnalysisCacheEntry.currentVersion,
               entry.fileSize == item.fileSize {
                applyCachedEntry(entry, to: &item)
            }
            results.append(item)
        }

        return results.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    private static func applyCachedEntry(_ entry: PhotoAnalysisCacheEntry, to item: inout PhotoItem) {
        item.isScreenshot = entry.isScreenshot
        item.isDocumentLike = entry.isDocumentLike
        item.isTextImage = entry.isTextImage
        item.blurScore = entry.blurScore
        item.isBlurredOrShaky = entry.isBlurredOrShaky
        item.exposureIsBad = entry.exposureIsBad
        item.pHash = entry.pHash
        item.similarGroupId = entry.similarityGroupId
        if let kindRaw = entry.similarityKind {
            item.similarityKind = SimilarityGroupKind(rawValue: kindRaw)
        } else {
            item.similarityKind = nil
        }
        item.isLargeFile = item.fileSize > 15 * 1_024 * 1_024
    }
}
