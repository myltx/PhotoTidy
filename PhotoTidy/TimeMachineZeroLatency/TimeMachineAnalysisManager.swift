import Foundation
import Photos

actor TimeMachineAnalysisManager {
    private let analysisCache: PhotoAnalysisCacheStore
    private var pendingIds: [String] = []
    private var isRunning = false
    private let batchSize = 30

    init(analysisCache: PhotoAnalysisCacheStore = PhotoAnalysisCacheStore()) {
        self.analysisCache = analysisCache
    }

    func enqueue(ids: [String]) {
        guard !ids.isEmpty else { return }
        pendingIds.append(contentsOf: ids)
        guard !isRunning else { return }
        isRunning = true
        Task.detached { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        while !pendingIds.isEmpty {
            let chunk = Array(pendingIds.prefix(batchSize))
            pendingIds.removeFirst(min(chunk.count, pendingIds.count))
            await process(ids: chunk)
        }
        isRunning = false
    }

    private func process(ids: [String]) async {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var entries: [PhotoAnalysisCacheEntry] = []
        assets.enumerateObjects { asset, _, _ in
            let size = Self.estimatedSize(for: asset)
            let entry = PhotoAnalysisCacheEntry(
                localIdentifier: asset.localIdentifier,
                fileSize: size,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                isDocumentLike: false,
                isTextImage: false,
                blurScore: nil,
                isBlurredOrShaky: false,
                exposureIsBad: false,
                pHash: nil,
                featurePrintData: nil,
                similarityGroupId: nil,
                similarityKind: nil
            )
            entries.append(entry)
        }
        analysisCache.update(entries: entries)
    }

    private static func estimatedSize(for asset: PHAsset) -> Int {
        let resources = PHAssetResource.assetResources(for: asset)
        if let size = resources.first?.value(forKey: "fileSize") as? CLong {
            return Int(size)
        }
        let pixels = max(asset.pixelWidth, 1) * max(asset.pixelHeight, 1)
        return pixels * 4
    }
}
