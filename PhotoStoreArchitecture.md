# PhotoStore 统一架构设计

## 1. 背景
- 已具备三阶段加载链路（Metadata → Small Thumbnail → Full Size），但各模块的数据源、缓存策略分散。
- 目标：构建类似 Apple Photos 的统一 PhotoStore，让全相册/相似/专项筛选/仪表盘/时光机/跳过中心/待删区全部共享同一套索引、缓存与加载协议，实现 0ms 交互体验。

## 2. PhotoStore 体系图
```
SwiftUI Screens
    ↓
PhotoStoreFacade (ObservableObject)
    ├─ QueryRouter           # 解析 PhotoQueryIntent → Feed
    ├─ IndexCatalog          # 元数据 + 倒排索引 + 桶信息
    ├─ CacheCoordinator
    │     ├─ MemoryPool (L1)
    │     ├─ DiskVault (L2)
    │     └─ AssetBridge (L3, PHAsset)
    ├─ DataPipelines
    │     ├─ SequentialFeed (全相册/滑动)
    │     ├─ GroupedFeed    (相似/跳过中心)
    │     ├─ RankedFeed     (大文件/模糊/截图/文档)
    │     ├─ BucketedFeed   (时光机)
    │     └─ MetricsFeed    (仪表盘/待删/进度)
    ├─ PrefetchManager       # 统一预加载策略
    └─ AnalysisScheduler     # 后台分析/缓存写入
系统相册 (PHAsset/PHImageManager)
    ↕
DataLayer/Services (MetadataRepo, FeatureStore, ProgressStore, VisionDriver)
```

### 2.1 PhotoQuery & PhotoFeed
- `PhotoQueryIntent` → 只声明过滤、排序、分页方式（如 `.sequential(scope:.all)`, `.ranked(metric:.fileSizeDescending)`, `.bucketed(month: 2023-10)`）。
- `PhotoFeed` → `AsyncSequence`/`FeedState`，输出 `(assetID, metadataSnapshot, thumbnailState)`，UI 无需关心数据来源。
- QueryRouter 先命中 IndexCatalog，再 fallback 到 AnalysisScheduler 触发索引构建。

## 3. 缓存分层
### 3.1 L1 MemoryPool
| 分区 | 内容 | 生命周期 |
| ---- | ---- | -------- |
| `CurrentContext` | 滑动卡片前/当前/后一张的 metadata + medium 缩略 + Full Size 句柄 | 视图在前台 & 当前 session |
| `GroupHotset` | 当前相似组所有缩略 + 下一组首图 | 组浏览期间 |
| `TimelineWindow` | 当前月份 12 张缩略 + 下个月 5 张 | 页面停留 + 30s |
| `DashboardSnapshot` | 仪表盘统计、清理进度、最近操作 | 5 分钟或写入即失效 |

- 实现：`NSCache` + 生命周期 token，CacheCoordinator 负责打标签，视图离开时调用 `release(tag)`。

### 3.2 L2 DiskVault
| 分区 | 内容 | 清理策略 |
| ---- | ---- | -------- |
| `MetadataIndex` | `assetID → PhotoMetadata`（时间、尺寸、Vision 标签、分析版本） | 新分析覆盖旧版本；每月紧缩数据库 |
| `FeatureStore` | Vision 特征、哈希、模糊/文档得分 | LRU + 30 天未访问即清理 |
| `ThumbnailCache` | 小缩略 (200px) + Medium (600px) | 1–2 GB 容量，LRU |
| `GroupIndex` | 相似分组、专项分类（模糊/大文件/截图/文档） | `analysisVersion` 变化时批量失效 |
| `UserState` | 跳过/待删/清理进度 | 永续（SQLite） |

### 3.3 L3 AssetBridge
- 与 `PHAsset/PHImageManager` 打交道，仅当 L1/L2 miss 或需要最新原图时请求。
- 仍遵循三阶段：metadata（PHAsset）、小缩略（DiskVault）、大图（PHImageManager）。

### 3.4 读取优先级
`MemoryPool → DiskVault → PHAsset`，CacheCoordinator 统一追踪命中率并根据设备状态动态调整 L1/L2 容量。

## 4. 模块复用
- 所有模块共享 `MetadataIndex`：全相册/相似/时光机/仪表盘皆从同一快照读取。
- 相似/模糊/文档/大文件使用 `GroupIndex` 与 `FeatureStore` 存量索引，不再临时扫描。
- 待删、跳过中心、仪表盘统计都直接访问 `UserState` + `MetadataIndex`。
- 任何新类型（如“宠物照片”）仅需新增分析任务 → 写入 `FeatureStore`/`GroupIndex`，PhotoStore 即可提供新的 QueryIntent。

## 5. 预加载策略
- PrefetchManager 按模块产生 `PrefetchIntent`：
  - `Sequential(range: current±1)` → 滑动卡片。
  - `Group(groupID, lookaheadGroupID)` → 相似组。
  - `Bucket(month, tail:5)` → 时光机。
  - `Ranked(window: firstN)` → 大文件/模糊/截图/文档。
  - `Dashboard` → 小批量缩略图 + 最新统计。
- 每个 Intent 定义阶段：`metadataOnly`, `thumbnail`, `fullSize`，由策略表决定什么时候升级。
- 统一的 `PrefetchBudget` 根据设备内存、电量、网络自动缩放（低电量只做 metadata）。

## 6. 数据加载顺序
1. UI 发出 `PhotoQueryIntent`。
2. QueryRouter 在 IndexCatalog 中拉取 assetIDs（必要时等待 AnalysisScheduler 建索引）。
3. CacheCoordinator 批量查 L1/L2，返回命中与 miss 列表。
4. PrefetchManager 对 miss 发起系统请求（遵循三阶段）。
5. PhotoFeed 以流形式把结果送回 ViewModel；写操作通过 PhotoStore 写回索引/缓存并广播更新。

## 7. 分析任务调度
- `AnalysisScheduler` 维护去重队列（key = assetID + taskType + version）。
- 分类：
  - 惰性：页面首次访问时对当前窗口缺失的数据执行。
  - 后台批量：充电 + Wi-Fi + 空闲，按权重执行模糊/文档/相似/大文件。
  - 即时：用户操作后需要更新统计（如新增跳过/待删）。
- 结果写入 `FeatureStore` + `GroupIndex`，同时触发 PhotoStore invalidation（Feed 自动刷新）。
- 缓存格式：`SQLite` 表（`assetID | task | blob | version | updatedAt`），blob 存 JSON/Binary。

## 8. 性能保障
- 滑动卡片：PrefetchManager 在滚动事件第 1 帧就提交前后 assetID → MemoryPool，让 UI 始终有 ready 缩略图，必要时立即返回 metadata + skeleton。
- 相似/专项：进入页面先展示骨架（skeleton cells），PhotoFeed 读取缓存命中后逐步填充；GroupIndex 命中率≥95%。
- 时光机：BucketedFeed 只加载可视月份的 12 张 + 下个月 5 张；全屏时 reutilize Medium 缩略图。
- 仪表盘：DashboardSnapshot 常驻 L1，写操作将 snapshot 标记 dirty 并后台重建，不阻塞主线程。
- 5–10 万张：IndexCatalog 在内存仅保留 `assetID + 时间戳 + classification bitset`；其他字段按需分批查询，分页游标使用 `assetID` 而非 offset。

## 9. 改造步骤
1. 引入本文档所述模块骨架：`PhotoStoreFacade`, `IndexCatalog`, `CacheCoordinator`, `PrefetchManager`, `AnalysisScheduler`。
2. 重写 ViewModel/Views，让所有界面仅依赖 `PhotoQueryIntent` 与 `PhotoFeed`。
3. 将现有缓存（Vision/进度/跳过/待删）迁移至 DiskVault；集中由 PhotoStore 协调增删。
4. 完成后再扩展 Feature Toggle/测试覆盖，并以本文档作为长期架构规范。
