import Foundation
import Photos
import UIKit

final class TimeMachineImageManagerWrapper {
    private let cachingManager = PHCachingImageManager()
    private var inflight: [String: PHImageRequestID] = [:]
    private let requestOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        return options
    }()

    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) {
        let requestId = cachingManager.requestImage(
            for: asset,
            targetSize: targetSize * UIScreen.main.scale,
            contentMode: .aspectFill,
            options: requestOptions
        ) { [weak self] image, _ in
            completion(image)
            self?.inflight.removeValue(forKey: asset.localIdentifier)
        }
        inflight[asset.localIdentifier] = requestId
    }

    func cancelRequest(for identifier: String) {
        if let requestId = inflight.removeValue(forKey: identifier) {
            cachingManager.cancelImageRequest(requestId)
        }
    }

    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        cachingManager.startCachingImages(
            for: assets,
            targetSize: targetSize * UIScreen.main.scale,
            contentMode: .aspectFill,
            options: requestOptions
        )
    }

    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        cachingManager.stopCachingImages(
            for: assets,
            targetSize: targetSize * UIScreen.main.scale,
            contentMode: .aspectFill,
            options: requestOptions
        )
    }
}

private extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
