# 苹果级零延迟架构实施计划

本文将“Metadata → Thumbnail → Full Image”三阶段架构拆解为若干迭代步骤，便于在现有 PhotoTidy 项目中逐步落地。

## 阶段 0：准备与基线
1. **锁定目标模块**：优先迁移 Dashboard + 时光机（共享 Metadata & Thumbnail），随后是 Tinder 清理与专项处理。
2. **建立 Feature Toggle**：在 `FeatureToggles` 中增加 `enableApplePhotosArchitecture`，确保可灰度发布。
3. **记录当前性能**：保存 `xcodebuild -project PhotoTidy.xcodeproj ... clean build` 与 UI 首帧截图，作为对比基准。

## 阶段 1：MetadataStore 升级（Stage A）
1. 扩展 `MetadataSnapshot`：
   - 新增字段：`monthCoverAssetIds`、`monthDateRanges`、`categoryLastUpdatedAt`。
   - 更新 `MetadataCacheStore` 的读写逻辑与 schema version。
2. 调整 `MetadataRepository`：
   - 生成快照时带上封面 ID/时间范围。
   - 提供 `metadataPublisher` 给 UI/其它 Store。
3. UI 接入：
   - Dashboard、时光机等 ViewModel 改为只读 `MetadataSnapshot` 渲染首屏骨架。
   - 验证 `TimeMachineZeroLatencyViewModel` 读缓存即可渲染 4 年占位。

## 阶段 2：ThumbnailStore（Stage B）
1. 抽象 `ThumbnailRequest`/`ThumbnailHandle`：
   - 统一封装 `ImagePipeline`（内存 + 磁盘）与 `PHCachingImageManager`。
   - 支持 L1(NSCache 最近 3 张)、L2(磁盘)、L3(PhotoKit) 三层缓存。
2. 新建 `ThumbnailStore` actor：
   - 订阅 `MetadataStore`，根据封面 ID 和“需要的列表”预热缩略图。
   - 暴露 `func thumbnail(for assetId: String, target: ThumbnailTarget) async -> UIImage?`。
3. UI 改造：
   - `AssetThumbnailView`、`AssetRichPreviewView` 改为依赖 `ThumbnailStore` 返回的 `ImageState`（loading/success/failure）。
   - Dashboard 卡片 & 时光机月份封面优先显示 Stage B 缓存。

## 阶段 3：PhotoSessionManager（分页/虚拟化）
1. 设计 `PhotoSession`:
   - Scope（all / month / category / album）、Batch Size、Prefetch 策略。
   - 统一使用 `PhotoRepository.fetchNextBatch`，支持增量更新。
2. 实现 `PhotoSessionManager` actor：
   - 维护 session → 当前 offset、已加载 descriptors、keep-alive 缓存。
   - 提供 `onAppear(index:)` / `loadMoreIfNeeded()` 回调给 UI。
3. 迁移模块：
   - `TimeMachineMonthDetailViewModel` 改为根据 session 获取 batch，而非一次性读取整月。
   - `PhotoCleanupViewModel` 的 Tinder 会话改用 session 数据源；`monthItems` 逻辑退场。

## 阶段 4：FullImageStore（Stage C）
1. 将 `LargeImagePager` 提升为 `FullImageStore`：
   - 支持多 session 并行 window（每个 session 3 张）。
   - 统一调度 `PHCachingImageManager` 的高分辨率请求与解码线程池。
2. 替换 UI：
   - `PhotoCardView` / 全屏预览 / 相似对比统一从 `FullImageStore` 取图，避免重复加载。
   - 引入 `FullImageTicket` 表示当前、前、后一张的状态（loading/ready）。

## 阶段 5：AnalysisStore & 状态同步
1. 重构 `PhotoAnalysisCacheStore` 为 actor：
   - 提供 `updates` AsyncSequence，实现增量推送。
   - 支持 diff（新增/删除/字段变更）。
2. 新建 `AnalysisStore`：
   - 背景任务写入缓存后，通知 `MetadataStore` / `PhotoSessionManager` / `ThumbnailStore` 刷新标签。
3. UI 联动：
   - 相似/模糊/大文件标签来自 Stage B 缓存，而非实时计算。
   - 时光机、待删区使用同一份分析状态。

## 阶段 6：UI 迁移与清理
1. 渐进替换各 ViewModel：
   - Dashboard、专项处理、待删区、跳过中心逐个迁移至新的数据源。
   - 删除旧的 `ingestAssets`、`monthItems`、`prefetchMonthAssetsIfNeeded` 等逻辑。
2. Skeleton & fallback：
   - 所有页面默认渲染骨架，Stage B/C 则以数据驱动替换。
3. 文档与测试：
   - 更新 `TimeMachineRevamp.md`、`ZeroLatencyLoadingArchitecture.md` 记录新的数据流。
   - 为 `MetadataStore`、`ThumbnailStore`、`PhotoSessionManager` 增加 XCTest（mock PhotoRepository/Cache）。

## 阶段 7：灰度与监控
1. 通过 `FeatureToggles.enableApplePhotosArchitecture` 控制灰度人群。
2. 收集性能指标（首帧时间、滚动掉帧、内存占用）。
3. 完成全量切换后，移除旧实现与 Toggle。

> **实施建议**：每个阶段完成后都应打 Tag/PR，附上 `xcodebuild` 结果与 UI 截图，确保可随时回滚。
