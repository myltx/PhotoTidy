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
        let currentAssets = assets
        guard !currentAssets.isEmpty else { return [:] }
        let indexes = [centerIndex, centerIndex + 1, centerIndex + 2].filter {
            $0 >= 0 && $0 < currentAssets.count
        }
        guard !indexes.isEmpty else {
            trimCache(keeping: [])
            return cache
        }

        for index in indexes {
            guard index >= 0 && index < currentAssets.count else { continue }
            let asset = currentAssets[index]
            let identifier = asset.localIdentifier
            if cache[identifier] == nil {
                if let image = await requestImage(for: asset) {
                    cache[identifier] = image
                    order.append(identifier)
                }
            }
        }

        let keepSet = Set(indexes.compactMap { idx -> String? in
            guard idx >= 0 && idx < currentAssets.count else { return nil }
            return currentAssets[idx].localIdentifier
        })
        trimCache(keeping: keepSet)
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
