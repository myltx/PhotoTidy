import Foundation
import Photos
import UniformTypeIdentifiers

/// 从系统相册读取真实 PHAsset，并转换为 PhotoAssetMetadata
struct PhotoLibraryBootstrapper {
    func loadAssets(limit: Int) -> [PhotoAssetMetadata] {
        guard ensureAuthorization() else { return [] }
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAllBurstAssets = false
        if limit > 0 {
            fetchOptions.fetchLimit = limit
        }
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var results: [PhotoAssetMetadata] = []
        results.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            if let metadata = makeMetadata(from: asset) {
                results.append(metadata)
            }
        }
        return results
    }
}

private extension PhotoLibraryBootstrapper {
    func ensureAuthorization() -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            let semaphore = DispatchSemaphore(value: 0)
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                status = newStatus
                semaphore.signal()
            }
            semaphore.wait()
        }
        return status == .authorized || status == .limited
    }

    func makeMetadata(from asset: PHAsset) -> PhotoAssetMetadata? {
        let resources = PHAssetResource.assetResources(for: asset)
        let captureDate = asset.creationDate ?? asset.modificationDate ?? Date()
        let byteSize = estimatedSize(for: asset, resources: resources)
        var tags: PhotoClassification = []
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            tags.insert(.screenshot)
        }
        if byteSize > 20_000_000 {
            tags.insert(.largeFile)
        }
        let palette = palette(for: asset.localIdentifier)
        let score = Double.random(in: 0.45...0.95)
        let blurScore = Double.random(in: 0.2...0.9)
        let documentScore = Double.random(in: 0.2...0.9)
        let similarityScore = Double.random(in: 0.2...0.9)

        let fileName = resources.first?.originalFilename ?? defaultFilename(for: asset)
        let mediaType = resolveMediaType(for: asset, resources: resources)
        let albumName = collectionName(for: asset)

        return PhotoAssetMetadata(
            id: asset.localIdentifier,
            captureDate: captureDate,
            fileName: fileName,
            byteSize: byteSize,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            mediaType: mediaType,
            albumName: albumName,
            tags: tags,
            groupIdentifier: nil,
            decision: .clean,
            palette: palette,
            score: score,
            blurScore: blurScore,
            documentScore: documentScore,
            similarityScore: similarityScore
        )
    }

    func estimatedSize(for asset: PHAsset, resources: [PHAssetResource]) -> Int {
        if let resource = resources.first,
           let size = resource.value(forKey: "fileSize") as? CLong {
            return Int(size)
        }
        let pixels = max(asset.pixelWidth, 1) * max(asset.pixelHeight, 1)
        return pixels * 4
    }

    func palette(for identifier: String) -> ThumbnailPalette {
        let hash = abs(identifier.hashValue)
        let start = colorHex(from: hash)
        let end = colorHex(from: hash &* 31)
        return ThumbnailPalette(startHex: start, endHex: end)
    }

    func colorHex(from value: Int) -> String {
        let r = (value >> 16) & 0xFF
        let g = (value >> 8) & 0xFF
        let b = value & 0xFF
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    func resolveMediaType(for asset: PHAsset, resources: [PHAssetResource]) -> PhotoAssetMetadata.MediaType {
        if asset.mediaType == .video {
            return .video
        }
        if asset.mediaSubtypes.contains(.photoLive) {
            return .live
        }
        if resources.contains(where: { resource in
            guard let type = UTType(resource.uniformTypeIdentifier) else { return false }
            return type == .gif || type.conforms(to: .gif)
        }) {
            return .gif
        }
        return .photo
    }

    func defaultFilename(for asset: PHAsset) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: asset.creationDate ?? Date())
        switch asset.mediaType {
        case .video:
            return "MOV_\(timestamp).MOV"
        default:
            return "IMG_\(timestamp).JPG"
        }
    }

    func collectionName(for asset: PHAsset) -> String {
        let options = PHFetchOptions()
        options.fetchLimit = 1
        let userCollections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: options)
        if userCollections.count > 0 {
            return userCollections.object(at: 0).localizedTitle ?? "所有照片"
        }
        let smartCollections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .smartAlbum, options: options)
        if smartCollections.count > 0 {
            return smartCollections.object(at: 0).localizedTitle ?? "所有照片"
        }
        return "所有照片"
    }
}
