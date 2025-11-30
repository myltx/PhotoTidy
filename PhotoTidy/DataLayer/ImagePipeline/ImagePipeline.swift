import Foundation
import Photos
import UIKit

struct ImageRequestToken {
    fileprivate let id: UUID
    fileprivate let cancelClosure: () -> Void

    init(id: UUID = UUID(), cancelClosure: @escaping () -> Void) {
        self.id = id
        self.cancelClosure = cancelClosure
    }

    func cancel() {
        cancelClosure()
    }

    static let noop = ImageRequestToken(id: UUID()) {}
}

/// 统一的图片加载/缓存通道，封装 Memory + Disk cache 以及批量预热能力
final class ImagePipeline {
    private let cachingManager = PHCachingImageManager()
    private let requestOptions: PHImageRequestOptions
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCache: ImageDiskCache
    private let lock = NSLock()
    private var inFlight: [UUID: PHImageRequestID] = [:]

    init(memoryLimitBytes: Int = 120 * 1_024 * 1_024, diskCache: ImageDiskCache = ImageDiskCache()) {
        self.diskCache = diskCache
        self.requestOptions = PHImageRequestOptions()
        self.requestOptions.deliveryMode = .opportunistic
        self.requestOptions.resizeMode = .fast
        self.requestOptions.isNetworkAccessAllowed = false
        self.requestOptions.isSynchronous = false
        self.memoryCache.totalCostLimit = memoryLimitBytes
    }

    @discardableResult
    func requestImage(
        for descriptor: AssetDescriptor,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        completion: @escaping (UIImage?) -> Void
    ) -> ImageRequestToken {
        let pixelSize = CGSize(width: targetSize.width * UIScreen.main.scale, height: targetSize.height * UIScreen.main.scale)
        let cacheKey = cacheKey(for: descriptor.id, targetSize: pixelSize, mode: contentMode)
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            completion(cached)
            return .noop
        }
        if let diskImage = diskCache.image(forKey: cacheKey) {
            memoryCache.setObject(diskImage, forKey: cacheKey as NSString, cost: diskImage.diskCost)
            completion(diskImage)
            return .noop
        }
        let token = UUID()
        let requestId = cachingManager.requestImage(
            for: descriptor.asset,
            targetSize: pixelSize,
            contentMode: contentMode,
            options: requestOptions
        ) { [weak self] image, _ in
            if let image {
                self?.memoryCache.setObject(image, forKey: cacheKey as NSString, cost: image.diskCost)
                self?.diskCache.store(image, forKey: cacheKey)
            }
            completion(image)
            self?.removeRequest(id: token)
        }
        store(requestId: requestId, for: token)
        return ImageRequestToken(id: token) { [weak self] in
            self?.cancelRequest(id: token)
        }
    }

    func prefetch(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        let pixelSize = CGSize(width: targetSize.width * UIScreen.main.scale, height: targetSize.height * UIScreen.main.scale)
        cachingManager.startCachingImages(
            for: assets,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: requestOptions
        )
    }

    func stopPrefetching(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        let pixelSize = CGSize(width: targetSize.width * UIScreen.main.scale, height: targetSize.height * UIScreen.main.scale)
        cachingManager.stopCachingImages(
            for: assets,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: requestOptions
        )
    }

    func cancelAll() {
        lock.lock()
        let identifiers = inFlight
        inFlight.removeAll()
        lock.unlock()
        identifiers.values.forEach { cachingManager.cancelImageRequest($0) }
    }

    private func store(requestId: PHImageRequestID, for token: UUID) {
        lock.lock()
        inFlight[token] = requestId
        lock.unlock()
    }

    private func removeRequest(id: UUID) {
        lock.lock()
        inFlight.removeValue(forKey: id)
        lock.unlock()
    }

    private func cancelRequest(id: UUID) {
        lock.lock()
        if let requestId = inFlight.removeValue(forKey: id) {
            lock.unlock()
            cachingManager.cancelImageRequest(requestId)
        } else {
            lock.unlock()
        }
    }

    private func cacheKey(for identifier: String, targetSize: CGSize, mode: PHImageContentMode) -> String {
        "\(identifier)_\(Int(targetSize.width))x\(Int(targetSize.height))_\(mode.rawValue)"
    }
}

private extension UIImage {
    var diskCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
