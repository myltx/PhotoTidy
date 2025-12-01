import Foundation
import Photos

/// 查询条件，支持“全部”“某个月份”“指定相册”等多种 scope
struct PhotoQuery: Hashable {
    enum Scope: Hashable {
        case all
        case month(year: Int, month: Int)
        case album(identifier: String)
    }

    let scope: Scope
    var includeVideos: Bool

    init(scope: Scope = .all, includeVideos: Bool = true) {
        self.scope = scope
        self.includeVideos = includeVideos
    }

    static let all = PhotoQuery()
}

/// 一个最小化的真实资源描述，仅包含 UI 需要的字段
struct AssetDescriptor: Identifiable {
    let id: String
    let asset: PHAsset
    let creationDate: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let byteSize: Int

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate ?? asset.modificationDate ?? Date()
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.byteSize = AssetDescriptor.estimatedSize(for: asset)
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

/// PhotoRepository 负责真实资源的分页加载、Scope 切换与任务取消
actor PhotoRepository {
    private var baseFetchResult: PHFetchResult<PHAsset>?
    private var scopedFetchResults: [PhotoQuery: PHFetchResult<PHAsset>] = [:]
    private var cachedAlbums: [String: PHAssetCollection] = [:]
    private var pagingState: [PhotoQuery: Int] = [:]

    func bootstrapLibraryIfNeeded() async {
        guard baseFetchResult == nil else { return }
        let status = await MainActor.run {
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return }
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        baseFetchResult = PHAsset.fetchAssets(with: options)
    }

    func resetPaging(for query: PhotoQuery) {
        pagingState[query] = 0
    }

    func reloadLibrary() {
        baseFetchResult = nil
        scopedFetchResults.removeAll()
        pagingState.removeAll()
    }

    func fetchNextBatch(query: PhotoQuery = .all, batchSize: Int) async -> [AssetDescriptor] {
        await bootstrapLibraryIfNeeded()
        guard let fetchResult = fetchResult(for: query) else { return [] }
        let start = pagingState[query] ?? 0
        guard start < fetchResult.count else { return [] }
        let upperBound = min(start + batchSize, fetchResult.count)
        let range = start..<upperBound
        pagingState[query] = upperBound
        return collectDescriptors(from: fetchResult, range: range)
    }

    func prefetchMonth(_ year: Int, month: Int, limit: Int) async -> [AssetDescriptor] {
        let query = PhotoQuery(scope: .month(year: year, month: month))
        let result = fetchResult(for: query) ?? makeFetchResult(for: query)
        guard let result else { return [] }
        let clampedLimit = min(limit, result.count)
        return collectDescriptors(from: result, range: 0..<clampedLimit)
    }

    func fetchAssets(
        forMomentIdentifiers identifiers: [String],
        limit: Int?
    ) async -> [AssetDescriptor] {
        await bootstrapLibraryIfNeeded()
        guard !identifiers.isEmpty else { return [] }
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: identifiers, options: nil)
        var descriptors: [AssetDescriptor] = []
        var seen = Set<String>()
        let assetOptions = PHFetchOptions()
        assetOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        collections.enumerateObjects { collection, _, stop in
            let assets = PHAsset.fetchAssets(in: collection, options: assetOptions)
            assets.enumerateObjects { asset, _, stopAssets in
                if seen.contains(asset.localIdentifier) { return }
                descriptors.append(AssetDescriptor(asset: asset))
                seen.insert(asset.localIdentifier)
                if let limit, descriptors.count >= limit {
                    stopAssets.pointee = true
                    stop.pointee = true
                }
            }
        }
        return descriptors
    }

    func assets(for identifiers: [String]) async -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    func assetIdentifiers(forMonth year: Int, month: Int) async -> [String] {
        await bootstrapLibraryIfNeeded()
        let query = PhotoQuery(scope: .month(year: year, month: month))
        guard let fetchResult = fetchResult(for: query) ?? makeFetchResult(for: query) else { return [] }
        var identifiers: [String] = []
        fetchResult.enumerateObjects { asset, _, _ in
            identifiers.append(asset.localIdentifier)
        }
        return identifiers
    }

    func assetIdentifiers(forMomentIdentifiers identifiers: [String]) async -> [String] {
        await bootstrapLibraryIfNeeded()
        guard !identifiers.isEmpty else { return [] }
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: identifiers, options: nil)
        var ids: [String] = []
        collections.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                ids.append(asset.localIdentifier)
            }
        }
        return ids
    }

    private func fetchResult(for query: PhotoQuery) -> PHFetchResult<PHAsset>? {
        if let cached = scopedFetchResults[query] {
            return cached
        }
        guard let result = makeFetchResult(for: query) else { return nil }
        scopedFetchResults[query] = result
        return result
    }

    private func makeFetchResult(for query: PhotoQuery) -> PHFetchResult<PHAsset>? {
        switch query.scope {
        case .all:
            return baseFetchResult
        case .month(let year, let month):
            let calendar = Calendar.current
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            guard let startDate = calendar.date(from: components),
                  let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) else { return nil }
            let predicate = NSPredicate(format: "(creationDate >= %@) AND (creationDate < %@)", startDate as NSDate, endDate as NSDate)
            let options = PHFetchOptions()
            options.predicate = predicate
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            return PHAsset.fetchAssets(with: options)
        case .album(let identifier):
            if let cachedResult = scopedFetchResults.first(where: { element in
                if case .album(let cachedId) = element.key.scope {
                    return cachedId == identifier
                }
                return false
            })?.value {
                return cachedResult
            }
            let collection: PHAssetCollection
            if let cached = cachedAlbums[identifier] {
                collection = cached
            } else {
                let fetch = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil)
                guard let found = fetch.firstObject else { return nil }
                cachedAlbums[identifier] = found
                collection = found
            }
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            return PHAsset.fetchAssets(in: collection, options: options)
        }
    }

    private func collectDescriptors(from fetchResult: PHFetchResult<PHAsset>, range: Range<Int>) -> [AssetDescriptor] {
        guard !range.isEmpty else { return [] }
        var descriptors: [AssetDescriptor] = []
        descriptors.reserveCapacity(range.count)
        for index in range {
            guard index < fetchResult.count else { break }
            let asset = fetchResult.object(at: index)
            descriptors.append(AssetDescriptor(asset: asset))
        }
        return descriptors
    }
}
