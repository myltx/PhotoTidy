
import Foundation

/// 清理模式
enum CleanupFilterMode: String, CaseIterable, Identifiable {
    case all = "全部"
    case similar = "相似照片"
    case blurred = "模糊/曝光"
    case screenshots = "截图"
    case documents = "文档"
    case large = "大文件"

    var id: String { rawValue }
}
