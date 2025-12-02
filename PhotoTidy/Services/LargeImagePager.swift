import Foundation
import Photos
import UIKit

actor LargeImagePager {
    private var assets: [PHAsset] = []
    private var targetSize: CGSize = .zero
    private var cache: [String: UIImage] = [:]
    private var order: [String] = []
    private let maxCacheCount = 4
    private let imageManager = PHCachingImageManager()

    func configure(assets: [PHAsset], targetSize: CGSize) {
        self.assets = assets
        self.targetSize = targetSize
        cache.removeAll()
        order.removeAll()
    }

    func ensureWindow(centerIndex: Int) async -> [String: UIImage] {
        guard !assets.isEmpty else { return [:] }
        let indexes = [centerIndex, centerIndex + 1, centerIndex + 2].filter {
            $0 >= 0 && $0 < assets.count
        }

        for index in indexes {
            let asset = assets[index]
            let identifier = asset.localIdentifier
            if cache[identifier] == nil {
                if let image = await requestImage(for: asset) {
                    cache[identifier] = image
                    order.append(identifier)
                }
            }
        }

        trimCache(keeping: Set(indexes.map { assets[$0].localIdentifier }))
        return cache
    }

    private func requestImage(for asset: PHAsset) async -> UIImage? {
        guard targetSize != .zero else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func trimCache(keeping keepSet: Set<String>) {
        var filteredOrder: [String] = []
        for id in order {
            if filteredOrder.contains(id) { continue }
            filteredOrder.append(id)
        }
        order = filteredOrder

        while cache.count > maxCacheCount {
            guard let candidate = order.first else { break }
            order.removeFirst()
            if keepSet.contains(candidate) { continue }
            cache.removeValue(forKey: candidate)
        }

        if cache.count > maxCacheCount {
            let overflow = cache.count - maxCacheCount
            for _ in 0..<overflow {
                if let id = order.first {
                    order.removeFirst()
                    cache.removeValue(forKey: id)
                }
            }
        }
    }
}
