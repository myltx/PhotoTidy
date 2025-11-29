import Foundation

enum SkippedPhotoSource: String, Codable, CaseIterable, Identifiable {
    case smart
    case similar
    case blurred
    case screenshots
    case documents
    case large
    case timeMachine
    case similarGroup
    case other
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .smart: return "智能清理"
        case .similar: return "相似照片"
        case .blurred: return "模糊照片"
        case .screenshots: return "截图/文档"
        case .documents: return "文档"
        case .large: return "大文件"
        case .timeMachine: return "时光机"
        case .similarGroup: return "对比模式"
        case .other: return "其他"
        }
    }
}

enum SkippedSourceCategory: String, CaseIterable, Identifiable {
    case timeMachine
    case smart
    case similar
    case other
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .timeMachine: return "时光机"
        case .smart: return "全相册整理"
        case .similar: return "相似照片"
        case .other: return "其他来源"
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .timeMachine: return 0
        case .smart: return 1
        case .similar: return 2
        case .other: return 3
        }
    }
}

extension SkippedPhotoSource {
    var category: SkippedSourceCategory {
        switch self {
        case .timeMachine:
            return .timeMachine
        case .smart:
            return .smart
        case .similar, .similarGroup:
            return .similar
        case .blurred, .screenshots, .documents, .large, .other:
            return .other
        }
    }
}

struct SkippedPhotoRecord: Codable, Identifiable, Equatable {
    let photoId: String
    var timestamp: Date
    var source: SkippedPhotoSource
    var isProcessed: Bool
    
    var id: String { photoId }
}
