import Foundation

actor SimilarGroupCacheStore {
    private struct Payload: Codable {
        let snapshots: [SimilarGroupSnapshot]
    }

    private let fileURL: URL
    private var snapshots: [SimilarGroupSnapshot] = []

    init(fileName: String = "SimilarGroupCache.json") {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
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
        let payload = Payload(snapshots: snapshots)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // ignore
        }
    }
}
