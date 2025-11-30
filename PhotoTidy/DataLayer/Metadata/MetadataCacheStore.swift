import Foundation

/// 负责元数据快照的读写，所有操作均在 actor 内串行化
actor MetadataCacheStore {
    private let fileURL: URL
    private var snapshot: MetadataSnapshot
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileName: String = "MetadataSnapshot_v1.json") {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = cachesDirectory.appendingPathComponent(fileName)
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: fileURL),
           let cached = try? decoder.decode(MetadataSnapshot.self, from: data),
           cached.schemaVersion == MetadataSnapshot.schemaVersion {
            self.snapshot = cached
        } else {
            self.snapshot = .empty
        }
    }

    func currentSnapshot() -> MetadataSnapshot {
        snapshot
    }

    func replace(with newSnapshot: MetadataSnapshot) async {
        snapshot = newSnapshot
        try? persistSnapshot()
    }

    private func persistSnapshot() throws {
        let data = try encoder.encode(snapshot)
        let tempURL = fileURL.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
    }
}
