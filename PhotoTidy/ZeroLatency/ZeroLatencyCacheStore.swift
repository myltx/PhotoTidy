import Foundation

actor ZeroLatencyCacheStore {
    static let schemaVersion = 1

    private let fileURL: URL
    private var cache: PhotoAnalysisCacheFile
    private var needsBootstrapFlag: Bool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ZeroLatencyCacheStore.defaultURL()
        self.encoder = ZeroLatencyCacheStore.makeEncoder()
        self.decoder = ZeroLatencyCacheStore.makeDecoder()
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? decoder.decode(PhotoAnalysisCacheFile.self, from: data),
           decoded.schemaVersion == ZeroLatencyCacheStore.schemaVersion {
            self.cache = decoded
        } else {
            self.cache = PhotoAnalysisCacheFile.empty(schemaVersion: ZeroLatencyCacheStore.schemaVersion)
        }
        self.needsBootstrapFlag = cache.assets.isEmpty
    }

    func currentSnapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            schemaVersion: cache.schemaVersion,
            totalCount: cache.totalCount,
            recentPreview: cache.recentPreview,
            monthlyCounts: cache.monthlyCounts,
            topLargeFiles: cache.topLargeFiles,
            analysisMeta: cache.analysisMeta,
            lastUpdated: cache.lastUpdated,
            needsBootstrap: needsBootstrapFlag
        )
    }

    func updateDashboard(
        totalCount: Int? = nil,
        monthlyCounts: [MonthlyCount]? = nil,
        recentPreview: [RecentPreviewItem]? = nil,
        topLargeFiles: [String]? = nil,
        lastUpdated: Date = Date()
    ) async {
        if let totalCount {
            cache.totalCount = totalCount
        }
        if let monthlyCounts {
            cache.monthlyCounts = monthlyCounts
        }
        if let recentPreview {
            cache.recentPreview = recentPreview
        }
        if let topLargeFiles {
            cache.topLargeFiles = topLargeFiles
        }
        cache.lastUpdated = lastUpdated
        needsBootstrapFlag = cache.recentPreview.isEmpty
        try? persistAndNotify()
    }

    func merge(entries: [String: ZeroLatencyCacheEntry]) async {
        guard !entries.isEmpty else { return }
        for (id, entry) in entries {
            cache.assets[id] = entry
        }
        cache.analysisMeta.lastSimilarityRun = Date()
        cache.lastUpdated = Date()
        needsBootstrapFlag = false
        try? persistAndNotify()
    }

    func markTopLargeFiles(_ ids: [String]) async {
        cache.topLargeFiles = ids
        cache.lastUpdated = Date()
        try? persistAndNotify()
    }

    func recalculateTopLargeFiles(limit: Int = 20) async {
        let sorted = cache.assets.sorted { $0.value.fileSize > $1.value.fileSize }
        cache.topLargeFiles = Array(sorted.prefix(limit).map(\.key))
        cache.lastUpdated = Date()
        try? persistAndNotify()
    }

    func needsAnalysis(for assetId: String, lastChangeDate: Date?) -> Bool {
        guard let entry = cache.assets[assetId] else { return true }
        guard let changeDate = lastChangeDate else { return false }
        return entry.lastAnalyzedAt < changeDate
    }

    private func persistAndNotify() throws {
        let data = try encoder.encode(cache)
        let tempURL = fileURL.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try fileManager.moveItem(at: tempURL, to: fileURL)
        notifySnapshotChange()
    }

    private func notifySnapshotChange() {
        let snapshot = currentSnapshot()
        NotificationCenter.default.post(
            name: .photoAnalysisCacheDidChange,
            object: nil,
            userInfo: ["snapshot": snapshot]
        )
    }

    private static func defaultURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("PhotoAnalysisCache_v\(schemaVersion).json")
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
