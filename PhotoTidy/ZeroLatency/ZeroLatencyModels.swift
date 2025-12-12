import Foundation
import Photos

// MARK: - Cache Schema Models
// 说明：ZeroLatency 的旧缓存 JSON schema（v1）仍需要这些模型做惰性迁移
// （见 PhotoAnalysisRepository.migrateFromZeroLatencyIfNeeded）。当前不再在 ZeroLatency 内部写盘。

struct RecentPreviewItem: Codable, Identifiable, Equatable {
    let id: String
    let thumb: String?
    let createdAt: Date
}

struct MonthlyCount: Codable, Equatable, Identifiable {
    let year: Int
    let month: Int
    let count: Int

    var id: String { "\(year)-\(month)" }
}

struct ZeroLatencyCacheEntry: Codable, Equatable {
    let fileSize: Int
    let isScreenshot: Bool
    let isVideo: Bool
    let sharpness: Double
    let similarGroupId: Int
    let featureHash: String
    let lastAnalyzedAt: Date
}

struct AnalysisMeta: Codable, Equatable {
    var lastSimilarityRun: Date?
    var version: String
}

struct PhotoAnalysisCacheFile: Codable {
    var schemaVersion: Int
    var lastUpdated: Date
    var totalCount: Int
    var recentPreview: [RecentPreviewItem]
    var monthlyCounts: [MonthlyCount]
    var assets: [String: ZeroLatencyCacheEntry]
    var topLargeFiles: [String]
    var analysisMeta: AnalysisMeta
}

extension PhotoAnalysisCacheFile {
    static func empty(schemaVersion: Int) -> PhotoAnalysisCacheFile {
        PhotoAnalysisCacheFile(
            schemaVersion: schemaVersion,
            lastUpdated: .distantPast,
            totalCount: 0,
            recentPreview: [],
            monthlyCounts: [],
            assets: [:],
            topLargeFiles: [],
            analysisMeta: AnalysisMeta(lastSimilarityRun: nil, version: "1.0.0")
        )
    }
}

struct DashboardSnapshot: Equatable {
    let schemaVersion: Int
    let totalCount: Int
    let recentPreview: [RecentPreviewItem]
    let monthlyCounts: [MonthlyCount]
    let topLargeFiles: [String]
    let analysisMeta: AnalysisMeta
    let lastUpdated: Date
    let needsBootstrap: Bool
}

extension DashboardSnapshot {
    static func placeholder() -> DashboardSnapshot {
        DashboardSnapshot(
            schemaVersion: 1,
            totalCount: 0,
            recentPreview: [],
            monthlyCounts: [],
            topLargeFiles: [],
            analysisMeta: AnalysisMeta(lastSimilarityRun: nil, version: "1.0.0"),
            lastUpdated: .distantPast,
            needsBootstrap: true
        )
    }
}

enum AnalysisState: Equatable {
    case idle
    case analyzing(progress: String)

    var statusText: String {
        switch self {
        case .idle:
            return "分析就绪"
        case .analyzing(let progress):
            return "分析中… \(progress)"
        }
    }
}

struct AssetItem: Identifiable {
    let id: String
    let asset: PHAsset
    let creationDate: Date
}

extension Notification.Name {
    static let photoAnalysisCacheDidChange = Notification.Name("photoAnalysisCacheDidChange")
}
