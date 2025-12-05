# PhotoTidy 数据架构提案

> 目标：在当前已经完成的静态页面基础上，设计一套可以支撑 Dashboard、滑动卡片、相似组、专项处理、时光机以及决策中心的统一数据架构，实现苹果照片 App 等级的“三阶段加载”（Metadata → Thumbnail → Full Size）体验。

---

## 1. 页面功能现状（静态）

| 模块 | 关键功能 | 数据粒度 |
| --- | --- | --- |
| 仪表盘（DashboardView） | 手机存储/已使用/可清理卡片、待删区/待确认数量、各专项（大文件、相似、文档截图、模糊）入口 | 设备使用统计、全局分类汇总 |
| 滑动卡片（CarouselReviewView） | 单张全屏预览，支持左右/上滑做“保留 / 待删 / 跳过”，展示文件名、时间、大小、媒体类型 | 单 Asset 列表顺序加载 |
| 相似组（GroupedReviewView） | 同组横向滚动，多选保留/删除，推荐保留角标，浮起式卡片样式 | 分组结构 + 组内 Asset |
| 专项处理（RankedReviewView） | 勾选多张图片加入待删区，选中态使用全局选中色 | 基于标签/评分的 Asset 列表 |
| 时光机（TimelineView） | 年份筛选 → 月份 mini-grid → 月份弹窗可勾选加入待删 | 按月聚合、月内 Asset 列表 |
| 决策中心（DecisionCenterView） | 待删区、待确认区分入口+列表、偏好设置，待确认支持批量“放回/删除/保留” | Pending / Skipped Asset 列表，用户偏好 |

> 这些页面当前全部使用静态或 Mock 数据，前端交互已经定型，等待数据层落地。

---

## 2. 数据域目标

1. **基础实体**
   - `PhotoAssetMetadata`：统一的 Metadata 载体，包含 id、拍摄时间、文件大小、相册、评分、标签、调色板等。
   - `PhotoGroupSnapshot`：相似组/连拍组快照，含组内成员与推荐保留。
   - `TimelineBucketSnapshot`：月度聚合数量、代表封面、待删统计。
   - `DashboardSnapshot`：设备容量、分类总数、进度条。

2. **用户动作**
   - `PhotoDecisionState`（clean/pendingDeletion/skipped/kept）
   - `DecisionPreference`（忽略收藏、删除是否弹框）
   - `PendingQueue` 与 `SkipQueue` 操作流水，支持撤销/回流。

3. **分析特征**
   - Vision 特征、模糊评分、文档评分、相似度向量。
   - FeatureStore 与 GroupIndex 写在 SQLite + FTS 表中，供 Ranked/Grouped 使用。

---

## 3. 统一数据架构（建议）

```
┌────────────┐
│PhotoKit /  │  Stage 3  (full size, lazy load on demand)
│原始相册    │
└────┬───────┘
     │
┌────▼──────────────┐
│PhotoLibraryBoot…  │  Ingestion 批量导入 Metadata + 轻量缩略图
└────┬──────────────┘
     │
┌────▼───────────────────────────────────────────────┐
│SQLite IndexCatalog + FeatureStore + GroupIndex     │
│  - MetadataIndex（核心字段）                       │
│  - TimelineIndex（capture_month, counts）          │
│  - FeatureStore（blur/doc/similarity）             │
│  - GroupIndex（相似组、推荐保留）                  │
└────┬───────────────────────────────────────────────┘
     │ Stage 1 (Metadata)
┌────▼────────────┐             ┌───────────────────┐
│CacheCoordinator │◀────────────│PrefetchManager    │
│  - MemoryPool   │   Stage 2   │意图感知预取       │
│  - DiskVault    │ (thumbnail) └───────────────────┘
└────┬────────────┘
     │
┌────▼───────────┐
│PhotoStore      │ 统一 Query Intent → FeedState
│  - datasetCache│  - Pagination
│  - AnalysisSched. + Worker
└────┬───────────┘
     │
┌────▼────────────┐
│PhotoStoreFacade │  主线程可观察对象，供 SwiftUI 使用
└────┬────────────┘
     │
┌────▼─────────────┐
│页面 (Dashboard… )│
└──────────────────┘
```

### 3.1 三阶段说明

| 阶段 | 载体 | 触发点 | 目标 |
| --- | --- | --- | --- |
| Stage 1: Metadata | SQLite IndexCatalog | 应用启动/刷新 Feed | 先展示骨架 + 元数据（时间/大小/评分） |
| Stage 2: Thumbnail | CacheCoordinator (MemoryPool→DiskVault) | PrefetchManager 基于 intent 预热（滑动前后、相似组 cover、年/月封面） | 200~600px 小缩略图，0ms 切换 |
| Stage 3: Full Size | PhotoKit / 原始文件 | 用户进入全屏/播放 live/video、需要高分辨率时 | 请求 PHImageManager，必要时写回 DiskVault 做局部缓存 |

### 3.2 Prefetch 策略（示例）

| Intent | Window | 备注 |
| --- | --- | --- |
| `.sequential(scope: .all)`（滑动卡片） | 当前 index 前后各 1 | PrefetchManager 感知 Carousel 的 `currentIndex`，调用 `prefetch(range:)` |
| `.grouped(.similar)` | 当前组 + 下一组所有成员 | 同组横向滚动，预热 LivePhoto/GIF 元素 |
| `.ranked(.blurred/.document)` | 当前分页 20 张 | 确保 grid 中所有卡片一次性就绪 |
| `.bucketed`（时光机） | 当前年份 2 个 section 的封面 + 月份 top5 asset | 点击月份弹窗后，继续按月份 asset 做增量预取 |

### 3.3 Analysis Scheduler

| 任务 | 触发 | 结果写入 |
| --- | --- | --- |
| Metadata 补全 | 第一次加载 sequential dataset | MetadataIndex (ISO8601 captureDate、album、size) |
| Vision Blur/Document | 进入 Ranked intent / Timeline month detail | FeatureStore（blur_score、document_score） |
| Similarity Grouping | 进入相似页面 / Dashboard 卡片统计 | GroupIndex（group_id、lead_asset_id、recommended_keep） |
| Cleanup Progress | 决策操作写入 | MetadataIndex.decision + PendingQueue |

---

## 4. 模块与数据流映射

| 页面 | 数据来源 | 依赖 |
| --- | --- | --- |
| Dashboard | `PhotoStoreFacade.dashboard`（由 `catalog.dashboard()` 生成） | MetadataIndex 聚合、DeviceStorageUsage（从 `DiskUsageProvider` 或系统 API） |
| Carousel Review | `PhotoFeedViewModel(intent: .sequential(scope: .all))` | PrefetchManager → CacheCoordinator → AssetPreviewView（Stage2） |
| Grouped Review | `intent: .grouped(.similar)` | GroupIndex + members Metadata；推荐保留字段写入 |
| Ranked Review | `intent: .ranked(kind)` | FeatureStore（blur/doc score）+ MetadataIndex tags |
| Timeline | `intent: .bucketed` + `PhotoFeedViewModel(intent: .sequential(scope: .month))` | TimelineIndex + Stage2 thumbnails |
| Decision Center | `intent: .pending(.pendingDeletion/.skipped)` + `DecisionPreference` | MetadataIndex.decision + PendingQueue；批量操作通过 PhotoStore APIs |

---

## 5. 落地建议

1. **先固化数据层**
   - 完成 `PhotoStoreDatabase` 的 MetadataIndex / FeatureStore / GroupIndex 表结构及 SQL，支持分页、FTS。
   - 接入真实 `PhotoLibraryBootstrapper`，并提供 Mock seed 作为 fallback。

2. **完善缓存管线**
   - `MemoryPool` 以 LRU 记录 `PhotoThumbnailDescriptor + UIImage` 缓存。
   - `DiskVault` 改写为实际缩略图（PNG/HEIF）文件夹 + SQLite 索引，而非 JSON。
   - `AssetPreviewView` 先查 CacheCoordinator，再决定是否调用 `PHImageManager`。

3. **统一决策写回**
   - 在 PhotoStore 暴露 `applyDecision(ids: state:)`，更新数据库并刷新相关 feed。
   - PrefetchManager 接收 `CacheTag(intent)`，完成队列释放。

4. **分析任务串联**
   - `AnalysisWorker` 根据 scheduler 队列（blur/doc/similarity）拉取 Asset ID，执行 Vision CoreML，写回 FeatureStore/GroupIndex，并通过 Facade 通知页面刷新。

5. **监控与日志**
   - `PhotoStoreEventLog` 按 intent 记录 cache 命中、prefetch 执行、分析时长，供开发调优。

---

通过以上架构，应用可以在保持当前 UI 交互的同时，逐步把数据管线替换为真实的三阶段加载，实现“滑动 0ms 切换、卡片列表即时显示、分析任务后台运行”的体验。建议先从 Timeline/Carousel 这类顺序需求最高的模块入手，验证 Prefetch + Cache 协作，再扩展到相似组与决策中心的批量操作。***
