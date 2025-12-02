import Foundation
import UIKit
import Photos

struct ThumbnailTarget {
    let size: CGSize
    let contentMode: PHImageContentMode

    static let timelineCover = ThumbnailTarget(
        size: CGSize(width: 160, height: 160),
        contentMode: .aspectFill
    )
}

actor ThumbnailStore {
    private let photoRepository: PhotoRepository
    private let imagePipeline: ImagePipeline
    private var descriptorCache: [String: AssetDescriptor] = [:]

    init(
        photoRepository: PhotoRepository = PhotoRepository(),
        imagePipeline: ImagePipeline = ImagePipeline(memoryLimitBytes: 60 * 1_024 * 1_024)
    ) {
        self.photoRepository = photoRepository
        self.imagePipeline = imagePipeline
    }

    func thumbnail(for assetId: String, target: ThumbnailTarget) async -> UIImage? {
        guard let descriptor = await descriptor(for: assetId) else { return nil }
        return await withCheckedContinuation { continuation in
            imagePipeline.requestImage(
                for: descriptor,
                targetSize: target.size,
                contentMode: target.contentMode
            ) { image in
                continuation.resume(returning: image)
            }
        }
    }

    private func descriptor(for assetId: String) async -> AssetDescriptor? {
        if let cached = descriptorCache[assetId] {
            return cached
        }
        let assets = await photoRepository.assets(for: [assetId])
        guard let asset = assets.first else {
            return nil
        }
        let descriptor = AssetDescriptor(asset: asset)
        descriptorCache[assetId] = descriptor
        return descriptor
    }
}
