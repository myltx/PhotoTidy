import Foundation
import UIKit
import Photos

/// 描述缩略图请求的规格（尺寸 + contentMode）
struct ThumbnailTarget: Hashable {
    let size: CGSize
    let contentMode: PHImageContentMode

    static let timelineCover = ThumbnailTarget(
        size: CGSize(width: 160, height: 160),
        contentMode: .aspectFill
    )

    static let smallGrid = ThumbnailTarget(
        size: CGSize(width: 140, height: 140),
        contentMode: .aspectFill
    )

    static let dashboardCard = ThumbnailTarget(
        size: CGSize(width: 220, height: 220),
        contentMode: .aspectFill
    )

    static let tinderCard = ThumbnailTarget(
        size: CGSize(width: 280, height: 280),
        contentMode: .aspectFill
    )

    static let detailFit = ThumbnailTarget(
        size: CGSize(width: 320, height: 320),
        contentMode: .aspectFit
    )

    func hash(into hasher: inout Hasher) {
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(contentMode.rawValue)
    }

    static func == (lhs: ThumbnailTarget, rhs: ThumbnailTarget) -> Bool {
        lhs.size == rhs.size && lhs.contentMode == rhs.contentMode
    }

    var pixelSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// 统一的缩略图仓库，负责 AssetDescriptor 缓存、ImagePipeline 请求与批量预热
actor ThumbnailStore {
    private let photoRepository: PhotoRepository
    private let imagePipeline: ImagePipeline

    private var descriptorCache: [String: AssetDescriptor] = [:]
    private var inflightTasks: [CacheKey: Task<UIImage?, Never>] = [:]

    init(
        photoRepository: PhotoRepository = PhotoRepository(),
        imagePipeline: ImagePipeline = ImagePipeline(memoryLimitBytes: 90 * 1_024 * 1_024)
    ) {
        self.photoRepository = photoRepository
        self.imagePipeline = imagePipeline
    }

    /// 请求指定 asset 的缩略图。内部使用 ImagePipeline（内存 + 磁盘缓存）。
    func thumbnail(for assetId: String, target: ThumbnailTarget) async -> UIImage? {
        let key = CacheKey(id: assetId, target: target)
        if let task = inflightTasks[key] {
            return await task.value
        }
        guard let descriptor = await descriptor(for: assetId) else { return nil }
        let task = Task<UIImage?, Never> {
            await requestImage(for: descriptor, target: target)
        }
        inflightTasks[key] = task
        let image = await task.value
        inflightTasks.removeValue(forKey: key)
        return image
    }

    /// 批量预热，避免滑动列表出现首帧加载。
    func preload(assetIds: [String], target: ThumbnailTarget) async {
        guard !assetIds.isEmpty else { return }
        let descriptors = await descriptors(for: assetIds)
        guard !descriptors.isEmpty else { return }
        let assets = descriptors.map { $0.asset }
        imagePipeline.prefetch(assets, targetSize: target.size)
    }

    /// 清空 Descriptor 缓存，供相册刷新时调用
    func resetCache() {
        descriptorCache.removeAll()
    }
}

private extension ThumbnailStore {
    struct CacheKey: Hashable {
        let id: String
        let target: ThumbnailTarget
    }

    func descriptor(for assetId: String) async -> AssetDescriptor? {
        if let cached = descriptorCache[assetId] {
            return cached
        }
        let assets = await photoRepository.assets(for: [assetId])
        guard let asset = assets.first else { return nil }
        let descriptor = AssetDescriptor(asset: asset)
        descriptorCache[assetId] = descriptor
        return descriptor
    }

    func descriptors(for assetIds: [String]) async -> [AssetDescriptor] {
        guard !assetIds.isEmpty else { return [] }
        var results: [AssetDescriptor] = []
        var missing: [String] = []
        for id in assetIds {
            if let cached = descriptorCache[id] {
                results.append(cached)
            } else {
                missing.append(id)
            }
        }
        guard !missing.isEmpty else { return results }
        let assets = await photoRepository.assets(for: missing)
        for asset in assets {
            let descriptor = AssetDescriptor(asset: asset)
            descriptorCache[descriptor.id] = descriptor
            results.append(descriptor)
        }
        return results
    }

    func requestImage(for descriptor: AssetDescriptor, target: ThumbnailTarget) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var resumed = false
            imagePipeline.requestImage(
                for: descriptor,
                targetSize: target.size,
                contentMode: target.contentMode
            ) { image in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
