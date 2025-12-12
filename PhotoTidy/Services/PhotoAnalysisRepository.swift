import Foundation

/// 分析缓存的统一入口：当前阶段内部仍使用 PhotoAnalysisCacheStore，
/// 但提供 Repository 接口，并惰性迁移 ZeroLatency 的旧缓存。
final class PhotoAnalysisRepository {
    private let store: PhotoAnalysisCacheStore
    private let zeroLatencyFileName = "PhotoAnalysisCache_v1.json"

    init(store: PhotoAnalysisCacheStore = PhotoAnalysisCacheStore()) {
        self.store = store
        migrateFromZeroLatencyIfNeeded()
    }

    // MARK: - Public API (与旧 Store 保持一致)

    func snapshot() -> [String: PhotoAnalysisCacheEntry] {
        store.snapshot()
    }

    func update(entries: [PhotoAnalysisCacheEntry]) {
        store.update(entries: entries)
    }

    func removeEntries(for identifiers: [String]) {
        store.removeEntries(for: identifiers)
    }

    func pruneMissingEntries(keeping identifiers: Set<String>) {
        store.pruneMissingEntries(keeping: identifiers)
    }

    // MARK: - Migration

    private func migrateFromZeroLatencyIfNeeded() {
        let existing = store.snapshot()
        guard existing.isEmpty else { return }

        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let url = caches.appendingPathComponent(zeroLatencyFileName)
        guard let data = try? Data(contentsOf: url) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cacheFile = try? decoder.decode(PhotoAnalysisCacheFile.self, from: data),
              cacheFile.schemaVersion == 1 else {
            return
        }

        // 只迁移无风险字段（fileSize/isScreenshot/isVideo），其它字段留空，避免语义偏差。
        var migrated: [PhotoAnalysisCacheEntry] = []
        migrated.reserveCapacity(cacheFile.assets.count)

        for (id, entry) in cacheFile.assets {
            let newEntry = PhotoAnalysisCacheEntry(
                localIdentifier: id,
                fileSize: entry.fileSize,
                isScreenshot: entry.isScreenshot,
                isDocumentLike: false,
                isTextImage: false,
                blurScore: nil,
                isBlurredOrShaky: false,
                exposureIsBad: false,
                pHash: nil,
                featurePrintData: nil,
                similarityGroupId: nil,
                similarityKind: nil
            )
            migrated.append(newEntry)
        }

        guard !migrated.isEmpty else { return }
        store.update(entries: migrated)
    }
}

