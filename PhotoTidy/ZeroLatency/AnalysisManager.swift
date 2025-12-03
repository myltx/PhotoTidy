import Foundation
import Photos
import UIKit
import CryptoKit

actor AnalysisManager {
    nonisolated(unsafe) var onStateChange: ((AnalysisState) -> Void)?

    private let cacheStore: ZeroLatencyCacheStore
    private var pendingAssets: [String: PHAsset] = [:]
    private var isProcessing = false
    private let chunkSize = 50
    private let backoffNanoseconds: UInt64 = 300_000_000

    init(cacheStore: ZeroLatencyCacheStore) {
        self.cacheStore = cacheStore
    }

    func enqueue(assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        for asset in assets {
            pendingAssets[asset.localIdentifier] = asset
        }
        guard !isProcessing else { return }
        isProcessing = true
        notify(state: .analyzing(progress: "准备中"))
        Task.detached(priority: .utility) { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        while true {
            try? Task.checkCancellation()
            let chunk = await nextChunk()
            if chunk.isEmpty { break }
            notify(state: .analyzing(progress: "\(chunk.count) 张"))
            let filtered = await filterPendingChunk(chunk)
            guard !filtered.isEmpty else {
                try? await Task.sleep(nanoseconds: backoffNanoseconds)
                continue
            }
            let entries = await AnalysisManager.process(chunk: filtered)
            await cacheStore.merge(entries: entries)
            await cacheStore.recalculateTopLargeFiles()
            try? await Task.sleep(nanoseconds: backoffNanoseconds)
        }
        isProcessing = false
        notify(state: .idle)
    }

    private func nextChunk() -> [PHAsset] {
        guard !pendingAssets.isEmpty else { return [] }
        let values = Array(pendingAssets.values.prefix(chunkSize))
        for asset in values {
            pendingAssets.removeValue(forKey: asset.localIdentifier)
        }
        return values
    }

    private func filterPendingChunk(_ chunk: [PHAsset]) async -> [PHAsset] {
        var filtered: [PHAsset] = []
        for asset in chunk {
            let changeDate = asset.modificationDate ?? asset.creationDate
            let needs = await cacheStore.needsAnalysis(for: asset.localIdentifier, lastChangeDate: changeDate)
            if needs {
                filtered.append(asset)
            }
        }
        return filtered
    }

    private func notify(state: AnalysisState) {
        onStateChange?(state)
    }

    private static func process(chunk: [PHAsset]) async -> [String: ZeroLatencyCacheEntry] {
        var result: [String: ZeroLatencyCacheEntry] = [:]
        for asset in chunk {
            if let entry = try? await analyze(asset: asset) {
                result[asset.localIdentifier] = entry
            }
        }
        return result
    }

    private static func analyze(asset: PHAsset) async throws -> ZeroLatencyCacheEntry {
        let imageResponse = try await requestImageData(for: asset)
        guard let image = UIImage(data: imageResponse.data), let cgImage = image.cgImage else {
            throw AnalysisError.invalidImage
        }
        let featureHash = computeFeatureHash(from: imageResponse.data)
        let blurScore = computeSharpness(for: cgImage)
        let fileSize = imageResponse.fileSize
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let isVideo = asset.mediaType == .video
        let groupId = abs(featureHash.hashValue % 10_000)
        return ZeroLatencyCacheEntry(
            fileSize: fileSize,
            isScreenshot: isScreenshot,
            isVideo: isVideo,
            sharpness: blurScore,
            similarGroupId: groupId,
            featureHash: featureHash,
            lastAnalyzedAt: Date()
        )
    }

    private struct ImageResponse {
        let data: Data
        let fileSize: Int
    }

    private enum AnalysisError: Error {
        case imageDataMissing
        case invalidImage
    }

    private static func requestImageData(for asset: PHAsset) async throws -> ImageResponse {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            PhotoKitThread.perform {
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data else {
                        continuation.resume(throwing: AnalysisError.imageDataMissing)
                        return
                    }
                    let resources = PHAssetResource.assetResources(for: asset)
                    let size = resources.first.flatMap { $0.value(forKey: "fileSize") as? Int } ?? data.count
                    continuation.resume(returning: ImageResponse(data: data, fileSize: size))
                }
            }
        }
    }

    private static func computeFeatureHash(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func computeSharpness(for image: CGImage) -> Double {
        let sampleSize = 64
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 0
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        guard let buffer = context.data else { return 0 }
        let pixels = buffer.bindMemory(to: UInt8.self, capacity: sampleSize * sampleSize)
        var totalDiff: Double = 0
        var count: Double = 0
        for y in 0..<sampleSize {
            for x in 0..<(sampleSize - 1) {
                let idx = y * sampleSize + x
                let diff = abs(Int(pixels[idx]) - Int(pixels[idx + 1]))
                totalDiff += Double(diff)
                count += 1
            }
        }
        return count > 0 ? totalDiff / count : 0
    }
}
