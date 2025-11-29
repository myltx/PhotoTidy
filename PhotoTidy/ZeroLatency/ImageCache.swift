import Foundation
import Photos
import UIKit

final class ImageCache {
    private let cachingManager = PHCachingImageManager()
    private let requestOptions: PHImageRequestOptions
    private let defaultTargetSize: CGSize
    private var cachedRange: Range<Int> = 0..<0

    init(tileSize: CGFloat = 200) {
        self.defaultTargetSize = CGSize(width: tileSize, height: tileSize)
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        self.requestOptions = options
    }

    func requestThumbnail(for asset: PHAsset, targetSize: CGSize? = nil) async -> UIImage? {
        await withCheckedContinuation { continuation in
            cachingManager.requestImage(
                for: asset,
                targetSize: (targetSize ?? defaultTargetSize) * UIScreen.main.scale,
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func updateCaching(fetchResult: PHFetchResult<PHAsset>, newRange: Range<Int>) {
        let clamped = clamp(range: newRange, upperBound: fetchResult.count)
        guard clamped != cachedRange else { return }
        let startRanges = rangesToAdd(current: cachedRange, new: clamped)
        let stopRanges = rangesToRemove(current: cachedRange, new: clamped)
        let assetsToStart = assets(in: startRanges, from: fetchResult)
        let assetsToStop = assets(in: stopRanges, from: fetchResult)
        if !assetsToStart.isEmpty {
            cachingManager.startCachingImages(
                for: assetsToStart,
                targetSize: defaultTargetSize * UIScreen.main.scale,
                contentMode: .aspectFill,
                options: requestOptions
            )
        }
        if !assetsToStop.isEmpty {
            cachingManager.stopCachingImages(
                for: assetsToStop,
                targetSize: defaultTargetSize * UIScreen.main.scale,
                contentMode: .aspectFill,
                options: requestOptions
            )
        }
        cachedRange = clamped
    }

    func stopCachingAll() {
        cachingManager.stopCachingImagesForAllAssets()
        cachedRange = 0..<0
    }

    private func assets(in ranges: [Range<Int>], from fetchResult: PHFetchResult<PHAsset>) -> [PHAsset] {
        guard !ranges.isEmpty else { return [] }
        var result: [PHAsset] = []
        for range in ranges {
            let clamped = clamp(range: range, upperBound: fetchResult.count)
            guard !clamped.isEmpty else { continue }
            for index in clamped {
                result.append(fetchResult.object(at: index))
            }
        }
        return result
    }

    private func rangesToAdd(current: Range<Int>, new: Range<Int>) -> [Range<Int>] {
        guard !new.isEmpty else { return [] }
        if current.isEmpty { return [new] }
        var ranges: [Range<Int>] = []
        if new.lowerBound < current.lowerBound {
            ranges.append(new.lowerBound..<min(current.lowerBound, new.upperBound))
        }
        if new.upperBound > current.upperBound {
            ranges.append(max(current.upperBound, new.lowerBound)..<new.upperBound)
        }
        return ranges
    }

    private func rangesToRemove(current: Range<Int>, new: Range<Int>) -> [Range<Int>] {
        guard !current.isEmpty else { return [] }
        if new.isEmpty { return [current] }
        var ranges: [Range<Int>] = []
        if new.lowerBound > current.lowerBound {
            ranges.append(current.lowerBound..<min(new.lowerBound, current.upperBound))
        }
        if new.upperBound < current.upperBound {
            ranges.append(max(new.upperBound, current.lowerBound)..<current.upperBound)
        }
        return ranges
    }

    private func clamp(range: Range<Int>, upperBound: Int) -> Range<Int> {
        guard upperBound > 0 else { return 0..<0 }
        let lower = max(0, min(range.lowerBound, upperBound))
        let upper = max(lower, min(range.upperBound, upperBound))
        return lower..<upper
    }
}

private extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
