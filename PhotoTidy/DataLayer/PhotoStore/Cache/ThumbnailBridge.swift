import Foundation
import Photos
import UIKit

/// 负责与 PHImageManager 协作，生成指定尺寸的缩略图
actor ThumbnailBridge {
    private let imageManager = PHCachingImageManager()

    func makeThumbnail(for asset: PhotoAssetMetadata, targetSize: CGSize) async -> Data? {
        guard let phAsset = asset.resolvedAsset else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            imageManager.requestImage(
                for: phAsset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = image.jpegData(compressionQuality: 0.85)
                continuation.resume(returning: data)
            }
        }
    }
}
