# Repository Guidelines

## 项目结构与模块组织
核心源码集中在 `PhotoTidy/`：`Views/` 存放所有 SwiftUI 画面，`ViewModels/` 维系 `PhotoCleanupViewModel`、`TimeMachineTimelineViewModel`。`Services/` 与 `DataLayer/` 实现 Photos/Vision 访问及缓存，`Utils/` 只保留可复用扩展；实验性零延迟流程位于 `ZeroLatency/` 与 `TimeMachineZeroLatency/`。资源置于 `Assets.xcassets`，根目录的设计文档与 `FeatureToggles.swift` 是理解新模块的必读材料。

## 构建、测试与开发命令
- `xed PhotoTidy.xcodeproj` —— 打开默认 scheme 并配置团队签名。
- `xcodebuild -project PhotoTidy.xcodeproj -scheme PhotoTidy -destination 'platform=iOS Simulator,name=iPhone 15' clean build` —— 验证主分支可编译。
- `xcodebuild test -project PhotoTidy.xcodeproj -scheme PhotoTidy -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:PhotoTidyTests` —— 运行 XCTest（首次需在 Xcode 创建 `PhotoTidyTests` 目标并启用 `@testable import PhotoTidy`）。

## 代码风格与命名约定
遵循 Swift 5.9、4 空格缩进与 `// MARK: - Section` 片段。类型、视图使用 PascalCase（如 `CleanerCardView`），属性与方法保持 camelCase；新的 Screen 必须成对引入 `FooView` 与 `FooViewModel`，共享状态交给 `PhotoCleanupViewModel`。功能试验请在 `FeatureToggles.swift` 新增布尔开关并提供默认值。

## 测试指引
仓库暂缺测试，但期望对 `Services/`、`DataLayer/`、`ZeroLatency/` 的公共 API 添加 `XCTestCase`。测试文件放在 `PhotoTidyTests/` 并镜像源目录，命名为 `ComponentScenarioExpectationTests`（示例 `PhotoAnalysisCacheStore_WhenHitMemoryCache_ReturnsSnapshotTests`）。以 70% 语句覆盖率为目标，运行前利用 `PhotoItem` mock 构建数据，避免读取真实相册。

## 提交与 PR 规范
Git 历史遵循 `type: emoji 摘要`（例：`feat: ✨ 优化异步加载流程`）；请选择 `feat`、`fix`、`docs`、`refactor`、`chore` 等前缀并保持简洁动词。PR 描述需包含改动背景、受影响 Tab、截图或屏录、`xcodebuild test` 输出以及所动 Feature Toggle/数据迁移；若涉及文档更新，请链接至 `TimeMachineRevamp.md` 或其它说明。

## 配置与安全提示
应用离线处理相册，请勿提交包含原始 PHAsset 标识、坐标或联系人信息的日志；必要时以哈希或匿名示例代替。修改 `PhotoAnalysisCacheStore`、`SmartCleanupProgressStore` 等缓存策略后同步更新 `SettingsView` 中的清理入口，并在 PR 中写明是否需引导用户执行二次清理。启用零延迟方案前确认 `FeatureToggles.useZeroLatencyArchitectureDemo` 默认为 false，并记录回退路径。
