import Foundation

actor SimilarGroupCacheStore {
    private struct Payload: Codable {
        let snapshots: [SimilarGroupSnapshot]
        let generatedAt: Date?
    }

    private let fileURL: URL
    private var snapshots: [SimilarGroupSnapshot] = []

    init(fileName: String = "SimilarGroupCache.json") {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let directory = urls.first ?? FileManager.default.temporaryDirectory
        self.fileURL = directory.appendingPathComponent(fileName)
        Task { await loadFromDisk() }
    }

    func currentSnapshots() -> [SimilarGroupSnapshot] {
        snapshots
    }

    func replace(with newSnapshots: [SimilarGroupSnapshot]) async {
        snapshots = newSnapshots
        persist()
    }

    func prune(keeping identifiers: Set<String>) async {
        guard !snapshots.isEmpty else { return }
        var changed = false
        let filtered: [SimilarGroupSnapshot] = snapshots.compactMap { snapshot in
            let validIds = snapshot.assetIds.filter { identifiers.contains($0) }
            guard validIds.count >= 2 else {
                changed = true
                return nil
            }
            let recommended = identifiers.contains(snapshot.recommendedAssetId) ? snapshot.recommendedAssetId : validIds.first!
            if validIds.count != snapshot.assetIds.count || recommended != snapshot.recommendedAssetId {
                changed = true
                return SimilarGroupSnapshot(
                    groupId: snapshot.groupId,
                    assetIds: validIds,
                    recommendedAssetId: recommended,
                    latestDate: snapshot.latestDate,
                    updatedAt: snapshot.updatedAt
                )
            }
            return snapshot
        }
        if changed {
            snapshots = filtered
            persist()
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            snapshots = payload.snapshots
        } catch {
            snapshots = []
        }
    }

    private func persist() {
        let payload = Payload(snapshots: snapshots, generatedAt: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // ignore
        }
    }
}
