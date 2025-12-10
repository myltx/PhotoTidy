import Foundation

/// JSON 持久化的相册分析缓存，所有数据仅保存在本地
final class PhotoAnalysisCacheStore {
    private struct CachePayload: Codable {
        let version: Int
        let generatedAt: Date?
        let assetCount: Int?
        let entries: [PhotoAnalysisCacheEntry]
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.phototidy.analysis-cache")
    private let fileURL: URL
    private var entries: [String: PhotoAnalysisCacheEntry] = [:]
    private var lastGeneratedAt: Date?
    private var lastAssetCount: Int?

    init(fileName: String = "PhotoAnalysisCache.json") {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let directory = urls.first ?? FileManager.default.temporaryDirectory
        self.fileURL = directory.appendingPathComponent(fileName)

        queue.sync {
            loadLocked()
        }
    }

    func snapshot() -> [String: PhotoAnalysisCacheEntry] {
        queue.sync { entries }
    }

    func update(entries newEntries: [PhotoAnalysisCacheEntry]) {
        guard !newEntries.isEmpty else { return }
        queue.async {
            for entry in newEntries {
                self.entries[entry.localIdentifier] = entry
            }
            self.persistLocked()
        }
    }

    func removeEntries(for identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        queue.async {
            for identifier in identifiers {
                self.entries.removeValue(forKey: identifier)
            }
            self.persistLocked()
        }
    }

    func pruneMissingEntries(keeping identifiers: Set<String>) {
        queue.async {
            let filtered = self.entries.filter { identifiers.contains($0.key) }
            if filtered.count != self.entries.count {
                self.entries = filtered
                self.persistLocked()
            }
        }
    }

    private func loadLocked() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = [:]
            return
        }
        do {
            let payload = try decoder.decode(CachePayload.self, from: data)
            guard payload.version == PhotoAnalysisCacheEntry.currentVersion else {
                entries = [:]
                return
            }
            entries = payload.entries.reduce(into: [String: PhotoAnalysisCacheEntry]()) { partialResult, entry in
                partialResult[entry.localIdentifier] = entry
            }
            lastGeneratedAt = payload.generatedAt
            lastAssetCount = payload.assetCount ?? payload.entries.count
        } catch {
            entries = [:]
            lastGeneratedAt = nil
            lastAssetCount = nil
        }
    }

    private func persistLocked(assetCount: Int? = nil) {
        let payload = CachePayload(
            version: PhotoAnalysisCacheEntry.currentVersion,
            generatedAt: Date(),
            assetCount: assetCount ?? entries.count,
            entries: Array(entries.values)
        )
        guard let data = try? encoder.encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastGeneratedAt = payload.generatedAt
            lastAssetCount = payload.assetCount
        } catch {
            // 忽略写入失败，等待下次再尝试
        }
    }
}
