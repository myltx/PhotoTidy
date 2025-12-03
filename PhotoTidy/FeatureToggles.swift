import Foundation

enum FeatureToggles {
    /// 控制是否在 UI 中展示重置/清空入口
    static let showCleanupResetControls = false
    /// 是否延迟真实照片分页加载，在用户进入模块时才启动
    static let lazyLoadPhotoSessions = true
    /// 始终启用苹果级三阶段架构（Metadata/Thumbnail/Full Image）
    static let enableApplePhotosArchitecture = true
}
