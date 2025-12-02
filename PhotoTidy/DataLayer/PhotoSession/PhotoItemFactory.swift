import Foundation
import Photos

struct PhotoItemFactory {
    static func makePhotoItem(for asset: PHAsset, estimatedSize: Int) -> PhotoItem {
        PhotoItem(
            id: asset.localIdentifier,
            asset: asset,
            pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
            fileSize: estimatedSize,
            creationDate: asset.creationDate ?? asset.modificationDate,
            isVideo: asset.mediaType == .video,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            pHash: nil,
            blurScore: nil,
            exposureIsBad: false,
            isBlurredOrShaky: false,
            isDocumentLike: false,
            isTextImage: false,
            isLargeFile: estimatedSize > 10 * 1024 * 1024,
            similarGroupId: nil,
            similarityKind: nil,
            assetType: nil,
            markedForDeletion: false
        )
    }

    static func applyCachedEntry(_ entry: PhotoAnalysisCacheEntry, to item: inout PhotoItem) {
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
        item.isLargeFile = item.fileSize > 15 * 1024 * 1024
    }
}
