import Foundation

/// 首屏仅需的轻量统计信息，完全基于元数据缓存构建
struct MetadataSnapshot: Codable, Equatable {
    struct MonthTotal: Codable, Equatable, Identifiable {
        let year: Int
        let month: Int
        let total: Int

        var id: String { "\(year)-\(month)" }
    }

    struct CategoryCounters: Codable, Equatable {
        var similar: Int
        var blurred: Int
        var screenshot: Int
        var document: Int
        var largeFile: Int
        var livePhoto: Int
        var video: Int

        static let empty = CategoryCounters(
            similar: 0,
            blurred: 0,
            screenshot: 0,
            document: 0,
            largeFile: 0,
            livePhoto: 0,
            video: 0
        )
    }

    static let schemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let totalCount: Int
    let monthTotals: [MonthTotal]
    let categoryCounters: CategoryCounters
    let deviceStorageUsage: DeviceStorageUsage
    let cachedAnalysisVersion: Int
    let needsBootstrap: Bool

    var monthTotalsDictionary: [String: Int] {
        monthTotals.reduce(into: [:]) { dict, entry in
            dict[entry.id] = entry.total
        }
    }

    static let empty = MetadataSnapshot(
        schemaVersion: MetadataSnapshot.schemaVersion,
        generatedAt: .distantPast,
        totalCount: 0,
        monthTotals: [],
        categoryCounters: .empty,
        deviceStorageUsage: .empty,
        cachedAnalysisVersion: 0,
        needsBootstrap: true
    )
}
