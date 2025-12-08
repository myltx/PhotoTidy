import Foundation

enum FeatureToggles {
    /// 控制是否在 UI 中展示重置/清空入口（功能仍保留，后续可随时开启）
    static let showCleanupResetControls = false
    /// 是否启用零延迟相册加载演示入口（切换到全新 RootView 用于演示）
    static let useZeroLatencyArchitectureDemo = false
}
