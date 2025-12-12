import Foundation

/// 轻量级分析元数据持久化（用于 ZeroLatency Dashboard 显示“最近更新”等信息）。
/// 不参与核心分析缓存的版本控制，独立 JSON 文件，读写失败自动降级。
actor AnalysisDashboardMetaStore {
    struct Meta: Codable, Equatable {
        var lastUpdated: Date
        var lastSimilarityRun: Date?
        var version: String
    }

    static let currentVersion = "1.0.0"

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var meta: Meta

    init(fileURL: URL? = nil, fileName: String = "AnalysisDashboardMeta.json") {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        self.fileURL = fileURL ?? docs.appendingPathComponent(fileName)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? dec.decode(Meta.self, from: data) {
            self.meta = decoded
        } else {
            self.meta = Meta(
                lastUpdated: .distantPast,
                lastSimilarityRun: nil,
                version: AnalysisDashboardMetaStore.currentVersion
            )
        }
    }

    func load() -> Meta {
        meta
    }

    func update(lastUpdated: Date? = nil, lastSimilarityRun: Date? = nil, version: String? = nil) {
        if let lastUpdated { meta.lastUpdated = lastUpdated }
        if let lastSimilarityRun { meta.lastSimilarityRun = lastSimilarityRun }
        if let version { meta.version = version }
        persistLocked()
    }

    private func persistLocked() {
        guard let data = try? encoder.encode(meta) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 忽略写入失败，等待下次再尝试
        }
    }
}

