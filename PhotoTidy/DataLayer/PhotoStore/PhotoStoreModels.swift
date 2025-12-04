import Foundation

// MARK: - Core Photo Types

struct PhotoAssetMetadata: Identifiable, Hashable, Codable {
    enum MediaType: String, Codable {
        case photo
        case live
        case video
        case gif
    }

    struct MonthKey: Hashable, Codable, CustomStringConvertible, Identifiable {
        let year: Int
        let month: Int

        init(date: Date, calendar: Calendar = .current) {
            let components = calendar.dateComponents([.year, .month], from: date)
            self.year = components.year ?? 1970
            self.month = components.month ?? 1
        }

        init(year: Int, month: Int) {
            self.year = year
            self.month = month
        }

        var description: String {
            "\(year)-\(String(format: "%02d", month))"
        }

        var title: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM"
            guard let date = formatter.date(from: description) else { return description }
            formatter.dateFormat = "yyyy年 M月"
            return formatter.string(from: date)
        }

        var id: String { description }
    }

    let id: String
    let captureDate: Date
    let fileName: String
    let byteSize: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let mediaType: MediaType
    let albumName: String
    var tags: PhotoClassification
    var groupIdentifier: String?
    var decision: PhotoDecisionState
    var palette: ThumbnailPalette
    var score: Double
    var blurScore: Double
    var documentScore: Double
    var similarityScore: Double

    var monthKey: MonthKey {
        MonthKey(date: captureDate)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: captureDate)
    }

    var mediaBadgeText: String {
        switch mediaType {
        case .photo: return "PHOTO"
        case .live: return "LIVE"
        case .video: return "VIDEO"
        case .gif: return "GIF"
        }
    }

    var aspectRatio: Double {
        Double(pixelWidth) / max(Double(pixelHeight), 1)
    }
}

struct ThumbnailPalette: Hashable, Codable {
    let startHex: String
    let endHex: String
}

struct PhotoThumbnailDescriptor: Hashable, Codable {
    enum Source: String, Codable {
        case memory
        case disk
        case skeleton
    }

    let assetId: String
    let palette: ThumbnailPalette
    let source: Source
}

struct PhotoGroupSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let confidence: Double
    let members: [PhotoAssetMetadata]

    var cover: PhotoAssetMetadata? { members.first }
}

struct TimelineBucketSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let monthKey: PhotoAssetMetadata.MonthKey
    let assetCount: Int
    let cover: PhotoAssetMetadata?
    let pendingCount: Int
    let blurredCount: Int
    let documentCount: Int
}

struct DashboardSnapshot: Hashable, Codable {
    struct CategoryCount: Hashable, Codable {
        var label: String
        var value: Int
        var accent: ThumbnailPalette
    }

    struct ProgressMeter: Hashable, Codable {
        var title: String
        var progress: Double
        var subtitle: String
    }

    var generatedAt: Date
    var totals: [CategoryCount]
    var progressMeters: [ProgressMeter]
    var pendingDeletion: Int
    var skipped: Int
    var monthlyHighlights: [TimelineBucketSnapshot]
    var storageUsage: DeviceStorageUsage

    func value(for label: String) -> Int? {
        totals.first(where: { $0.label == label })?.value
    }
}

struct DeviceStorageUsage: Hashable, Codable {
    var totalBytes: Int
    var usedBytes: Int
    var freeBytes: Int
    var clearableBytes: Int

    var formattedTotal: String { DeviceStorageUsage.format(bytes: totalBytes) }
    var formattedUsed: String { DeviceStorageUsage.format(bytes: usedBytes) }
    var formattedFree: String { DeviceStorageUsage.format(bytes: freeBytes) }
    var formattedClearable: String { DeviceStorageUsage.format(bytes: clearableBytes) }

    private static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal)
    }
}

enum PhotoDecisionState: String, Codable, Hashable {
    case clean
    case pendingDeletion
    case skipped
}

struct PhotoFeedItem: Identifiable, Hashable, Codable {
    enum Payload: Hashable, Codable {
        case asset(PhotoAssetMetadata)
        case group(PhotoGroupSnapshot)
        case bucket(TimelineBucketSnapshot)
    }

    let id: String
    let payload: Payload
    let thumbnail: PhotoThumbnailDescriptor
}

struct PhotoFeedCursor: Hashable, Codable {
    let offset: Int
    let context: String?
}

struct PhotoFeedState: Hashable, Codable {
    enum Status: String, Codable {
        case idle
        case loading
        case streaming
        case exhausted
    }

    let intent: PhotoQueryIntent
    var items: [PhotoFeedItem]
    var cursor: PhotoFeedCursor?
    var status: Status
}

struct PrefetchIntent: Hashable {
    enum Kind: Hashable {
        case sequential(range: Range<Int>)
        case group(groupId: String, lookahead: String?)
        case bucket(monthId: String)
        case ranked(window: Range<Int>)
        case dashboard
    }

    let kind: Kind
    let assetIdentifiers: [String]
}

struct CacheTag: Hashable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
}

struct PhotoStoreEventLog: Identifiable, Hashable, Codable {
    let id: UUID = .init()
    let timestamp: Date = Date()
    let description: String
}

struct PhotoClassification: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let blurred = PhotoClassification(rawValue: 1 << 0)
    static let document = PhotoClassification(rawValue: 1 << 1)
    static let screenshot = PhotoClassification(rawValue: 1 << 2)
    static let largeFile = PhotoClassification(rawValue: 1 << 3)
    static let textHeavy = PhotoClassification(rawValue: 1 << 4)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
