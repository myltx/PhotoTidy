import Foundation

/// 首屏仅需的轻量统计信息，完全基于元数据缓存构建
struct MetadataSnapshot: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case totalCount
        case monthTotals
        case monthMomentIdentifiers
        case monthCoverAssetIds
        case monthDateRanges
        case categoryCounters
        case deviceStorageUsage
        case cachedAnalysisVersion
        case needsBootstrap
    }
    struct MonthTotal: Codable, Equatable, Identifiable {
        let year: Int
        let month: Int
        let total: Int

        var id: String { "\(year)-\(month)" }
    }

    struct MonthDateRange: Codable, Equatable {
        let start: Date
        let end: Date
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

    static let schemaVersion = 2

    let schemaVersion: Int
    let generatedAt: Date
    let totalCount: Int
    let monthTotals: [MonthTotal]
    let monthMomentIdentifiers: [String: [String]]
    let monthCoverAssetIds: [String: String]
    let monthDateRanges: [String: MonthDateRange]
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
        monthMomentIdentifiers: [:],
        monthCoverAssetIds: [:],
        monthDateRanges: [:],
        categoryCounters: .empty,
        deviceStorageUsage: .empty,
        cachedAnalysisVersion: 0,
        needsBootstrap: true
    )
}

extension MetadataSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        monthTotals = try container.decode([MonthTotal].self, forKey: .monthTotals)
        monthMomentIdentifiers = try container.decodeIfPresent([String: [String]].self, forKey: .monthMomentIdentifiers) ?? [:]
        monthCoverAssetIds = try container.decodeIfPresent([String: String].self, forKey: .monthCoverAssetIds) ?? [:]
        monthDateRanges = try container.decodeIfPresent([String: MonthDateRange].self, forKey: .monthDateRanges) ?? [:]
        categoryCounters = try container.decode(CategoryCounters.self, forKey: .categoryCounters)
        deviceStorageUsage = try container.decode(DeviceStorageUsage.self, forKey: .deviceStorageUsage)
        cachedAnalysisVersion = try container.decode(Int.self, forKey: .cachedAnalysisVersion)
        needsBootstrap = try container.decode(Bool.self, forKey: .needsBootstrap)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(totalCount, forKey: .totalCount)
        try container.encode(monthTotals, forKey: .monthTotals)
        try container.encode(monthMomentIdentifiers, forKey: .monthMomentIdentifiers)
        try container.encode(monthCoverAssetIds, forKey: .monthCoverAssetIds)
        try container.encode(monthDateRanges, forKey: .monthDateRanges)
        try container.encode(categoryCounters, forKey: .categoryCounters)
        try container.encode(deviceStorageUsage, forKey: .deviceStorageUsage)
        try container.encode(cachedAnalysisVersion, forKey: .cachedAnalysisVersion)
        try container.encode(needsBootstrap, forKey: .needsBootstrap)
    }
}
