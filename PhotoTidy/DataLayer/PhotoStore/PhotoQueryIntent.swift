import Foundation

enum PhotoScope: Hashable, Codable {
    case all
    case month(PhotoAssetMetadata.MonthKey)
}

enum PhotoGroupKind: String, Codable, Hashable, CaseIterable {
    case similar
    case skipped
}

enum PhotoRankedKind: String, Codable, Hashable, CaseIterable {
    case largeFiles
    case blurred
    case documents
    case screenshots
}

enum PhotoPendingKind: String, Codable, Hashable, CaseIterable {
    case pendingDeletion
    case skipped
}

enum PhotoQueryIntent: Hashable, Codable {
    case sequential(scope: PhotoScope)
    case grouped(kind: PhotoGroupKind)
    case ranked(kind: PhotoRankedKind)
    case bucketed(month: PhotoAssetMetadata.MonthKey)
    case pending(kind: PhotoPendingKind)
    case dashboard

    var pageSize: Int {
        switch self {
        case .sequential:
            return 18
        case .grouped:
            return 12
        case .ranked:
            return 24
        case .bucketed:
            return 6
        case .pending:
            return 30
        case .dashboard:
            return 0
        }
    }

    var displayName: String {
        switch self {
        case .sequential(.all): return "全相册"
        case .sequential(.month(let key)): return "\(key.title)"
        case .grouped(let kind):
            switch kind {
            case .similar: return "相似照片"
            case .skipped: return "跳过中心"
            }
        case .ranked(let kind):
            switch kind {
            case .largeFiles: return "大文件"
            case .blurred: return "模糊照片"
            case .documents: return "文档 / 扫描件"
            case .screenshots: return "截图"
            }
        case .bucketed(let key):
            return "\(key.title)"
        case .pending(let kind):
            return kind == .pendingDeletion ? "待删区" : "跳过中心"
        case .dashboard:
            return "仪表盘"
        }
    }
}

extension PhotoQueryIntent {
    var cacheTag: CacheTag {
        CacheTag("intent-\(cacheKey)")
    }

    private var cacheKey: String {
        switch self {
        case .sequential(let scope):
            switch scope {
            case .all:
                return "sequential-all"
            case .month(let key):
                return "sequential-\(key.description)"
            }
        case .grouped(let kind):
            return "grouped-\(kind.rawValue)"
        case .ranked(let kind):
            return "ranked-\(kind.rawValue)"
        case .bucketed(let key):
            return "bucketed-\(key.description)"
        case .pending(let kind):
            return "pending-\(kind.rawValue)"
        case .dashboard:
            return "dashboard"
        }
    }
}
