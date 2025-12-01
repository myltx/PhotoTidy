import Foundation

enum FeatureToggles {
    /// 控制是否在 UI 中展示重置/清空入口（功能仍保留，后续可随时开启）
    static let showCleanupResetControls = false
    /// 是否启用零延迟相册加载演示入口
    static let useZeroLatencyArchitectureDemo = false
    /// 是否启用新的零延迟加载管线（MetadataRepository + PhotoRepository）
    static let enableZeroLatencyPipeline = true
    /// 是否延迟真实照片分页加载，在用户进入模块时才启动
    static let lazyLoadPhotoSessions = true
    /// 是否启用零延迟时光机模块
    static let useZeroLatencyTimeMachine = true
}
