import Foundation

enum DashboardDetail: Identifiable {
    case similar
    case blurry
    case screenshots
    case largeFiles
    case success

    var id: String {
        switch self {
        case .similar: return "similar"
        case .blurry: return "blurry"
        case .screenshots: return "screenshots"
        case .largeFiles: return "largeFiles"
        case .success: return "success"
        }
    }
}
