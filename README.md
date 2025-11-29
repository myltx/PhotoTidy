# PhotoTidy

PhotoTidy 是一款基于 SwiftUI + Photos/Vision 打造的本地智能相册清理 App。它专注于「快速整理」「可视化时间轴」「安全回收」等体验，所有分析均在本地完成，不上传任何个人数据。

## 功能亮点

- **智能清理仪表盘**：首页展示存储占用、继续上次整理、四大分类入口（相似、模糊、截图/文档、大文件）以及待删区。
- **全相册滑动整理**：`CleanerContainerView + CardStackView` 提供 Tinder 式左删右保留交互，还可“跳过”并记录来源。
- **专项场景处理**：`SimilarComparisonView`、`BlurryReviewView`、`ScreenshotDocumentView`、`LargeFilesView` 分别解决重复、失焦、截图/文档、超大文件等问题。
- **时光机**：`TimeMachineView` 以月份维度展示整理进度（`TimeMachineProgressStore`），支持按月继续或回顾。
- **待删区 & 跳过中心**：`TrashView` 集中处理待删照片；`SkippedPhotosView` 保存所有“跳过”记录，便于再处理。
- **设置/偏好**：`SettingsView` 含主题切换、偏好、系统权限、数据管理（待确认照片、跳过中心）以及高级操作入口，所有状态与 `PhotoCleanupViewModel` 同步。
- **本地缓存与分析**：`PhotoAnalysisCacheStore` 持久化 Vision 特征；`SmartCleanupProgressStore`、`SkippedPhotoStore` 等保存清理进度和用户选择。

## 目录结构

```
PhotoTidy/
├── Assets.xcassets/           # 品牌配色、背景、App Icon
├── FeatureToggles.swift       # 功能开关（如临时隐藏重置入口）
├── Models/                    # PhotoItem、MonthProgress、SkippedPhotoRecord...
├── Services/                  # PhotoAnalysisCacheStore、TimeMachineProgressStore 等
├── Utils/                     # 工具方法与扩展
├── ViewModels/
│   └── PhotoCleanupViewModel.swift   # 核心 ViewModel，负责数据、分析、导航
└── Views/
    ├── ContentView/MainAppView        # TabView 框架与权限处理
    ├── DashboardView/TimeMachineView/SettingsView...
    ├── CleanerContainerView/CardStackView          # 全相册整理流程
    ├── TrashView/SkippedPhotosView                 # 待删区与跳过中心
    └── Components/                                 # 通用 UI 组件
```

## 架构说明

- **MVVM + SwiftUI**：所有 Tab 共用 `PhotoCleanupViewModel`，通过 `@ObservedObject` / `@StateObject` 注入。
- **Photos/Vision 集成**：在本地使用 PHAsset + Vision FeaturePrint、pHash、模糊评分等指标，完全离线。
- **持久化策略**：
  - `SmartCleanupProgressStore`：记录全相册整理锚点与待删状态。
  - `TimeMachineProgressStore`：跟踪月份处理数量、跳过、删除等。
  - `SkippedPhotoStore`：维护“待确认”列表。
  - `UserDefaults`：保存主题与偏好。
- **功能开关**：`FeatureToggles.showCleanupResetControls` 控制敏感入口显隐，利于灰度。
- **导航策略**：设置页使用 `NavigationStack(path:)` + `SettingsRoute` 管理多级入口，跳过中心/待删区与外层 TabBar 行为一致。

## 环境要求

- macOS 14+ / Xcode 15+
- iOS 17+ 设备或模拟器（需支持 SwiftUI、Photos/Vision 新 API）
- 运行时需授权访问照片库

## 快速开始

1. 克隆仓库并进入根目录：
   ```bash
   git clone <repo_url>
   cd PhotoTidy
   ```
2. 打开 `PhotoTidy.xcodeproj`，配置 Team 与签名。
3. 选择真机或模拟器运行；首次启动授予相册权限即可开始分析。
4. 在三个 Tab 中体验：
   - **首页**：继续/开始整理、智能分类入口、待删区。
   - **时光机**：按月查看、继续处理或筛选。
   - **设置**：偏好、权限、数据管理（含待确认与跳过中心）。

## 隐私声明

所有照片分析、特征缓存、进度记录均在设备本地完成，不上传服务器。用户可通过设置中的高级操作清空缓存或重置进度。

## 后续规划

- 重新开放首页/时光机的重置入口（受 Feature Toggle 控制）。
- 扩展系统权限模块（通知、相机等）。
- 提升跳过中心筛选与批量操作体验。
- 引入更多 Vision 模型以增强重复/失焦识别效果。

欢迎提交 Issue 或 PR，共同完善 PhotoTidy！
