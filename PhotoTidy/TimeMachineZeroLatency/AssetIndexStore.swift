import Foundation

actor AssetIndexStore {
    private var indexes: [String: [String]] = [:]

    func cachedIds(for key: String) -> [String]? {
        indexes[key]
    }

    func cache(ids: [String], for key: String) {
        indexes[key] = ids
    }

    func batch(for key: String, offset: Int, limit: Int) -> AssetBatch {
        let ids = indexes[key] ?? []
        guard !ids.isEmpty else { return AssetBatch(ids: [], hasMore: false) }
        let start = min(offset, ids.count)
        let end = min(ids.count, offset + limit)
        let slice = Array(ids[start..<end])
        return AssetBatch(ids: slice, hasMore: end < ids.count)
    }
}
