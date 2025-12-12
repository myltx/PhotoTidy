# PhotoTidy 数据层重构设计（详细版）

> 目标：不调整任何 UI（Views）、不改变现有交互/语义，在数据获取、分析、缓存、用户状态与派生集合层面进行重构，使数据层可复用、可测试、可增量维护。

## 0. 背景与主要功能

应用主要功能（数据层需支持的查询/派生集合）：
1. 全相册处理（处理所有相册内容）。
2. 时光机处理（按年份分组，每年 12 个月，进入某月处理当月图片）。
3. 大文件处理。
4. 模糊图片处理。
5. 截图/文档处理。
6. 待确认图片（跳过的图片）。
7. 待删除图片。

## 1. 现状与问题

### 1.1 现有数据流概览
- **加载**：`PhotoLoader` 使用 PhotoKit 分页读取 `PHAsset`，并做预热缓存。
- **主分析缓存**：`PhotoAnalysisCacheStore` 将分析结果写入文档目录 JSON。
- **ZeroLatency 分析与缓存**：`AnalysisManager` + `ZeroLatencyCacheStore` 另写一份缓存 JSON（用于 Dashboard/零延迟展示）。
- **用户状态缓存**：`SmartCleanupProgressStore`、`TimeMachineProgressStore`、`SkippedPhotoStore` 分别用 UserDefaults 持久化。
- **派生集合/会话**：`PhotoCleanupViewModel` 内通过过滤和排序生成各模块数据。

### 1.2 核心问题
1. **ViewModel 过胖**  
   `PhotoCleanupViewModel` 同时负责：分页加载、后台分析、相似分组、缓存读写、用户状态持久化、派生集合与会话管理，导致耦合严重且难测试。
2. **分析缓存双体系**  
   `PhotoAnalysisCacheStore` 与 `ZeroLatencyCacheStore` 字段/时机不一致，存在统计与列表不同步风险。
3. **异步与线程模型混杂**  
   GCD + `Task.detached` + actor 并存，跨线程读写 `items/sessionItems` 的路径多，扩展风险大。
4. **派生集合无统一真相源**  
   大文件/模糊/截图&文档/相似/时光机月份/待确认/待删除均在 ViewModel 中临时计算，缺少统一的领域层描述。

## 2. 重构原则
1. **单一真相源（Single Source of Truth）**  
   以 assetId 为 key 的“照片记录”作为唯一数据实体，包含元数据、分析结果、用户状态三类信息。
2. **数据层负责“获取/存储/派生”，ViewModel 负责“桥接/状态/导航”**  
   ViewModel 保留现有 `@Published` 字段名称与含义（UI 绑定不变），内部从数据层订阅/取快照。
3. **缓存统一与可迁移**  
   重构后只保留一份分析缓存文件/存储，支持从旧缓存按需迁移。
4. **增量更新优先**  
   加载/分析/派生都支持增量而非全量重扫，确保大库体验不退化。

## 3. 新数据层架构

### 3.1 模块分层

```
Views (不改)
  ↑
ViewModels (瘦身，只桥接)
  ↑
PhotoDataController (编排层 / 入口)
  ↑
Repositories / Stores (数据源与持久化)
  ↑
PhotoKit / 本地文件 / UserDefaults
```

### 3.2 领域模型（Domain）

#### 3.2.1 PhotoRecord（内部主模型）
- 数据层内部使用，不直接暴露给 UI。
- 结构：
  - `assetId: String`
  - `asset: PHAsset`
  - `metadata: AssetMetadata`
  - `analysis: AnalysisResult?`
  - `userState: UserState`

#### 3.2.2 AssetMetadata
- 对应现有 `PhotoItem` 的基础字段：
  - `pixelSize`
  - `fileSize`
  - `creationDate`
  - `isVideo`
  - `isScreenshot`（系统 subtype）
  - `modificationDate`（用于缓存失效）

#### 3.2.3 AnalysisResult
- 对应现有分析字段：
  - `blurScore: Double?`
  - `exposureIsBad: Bool`
  - `isBlurredOrShaky: Bool`
  - `isDocumentLike: Bool`
  - `isTextImage: Bool`
  - `pHash: UInt64?`
  - `featurePrintData: Data?`
  - `similarGroupId: Int?`
  - `similarityKind: SimilarityGroupKind?`
  - `assetType: AssetType?`（综合分类）
  - `lastAnalyzedAt: Date`
  - `version: Int`

#### 3.2.4 UserState
- 来自用户操作与进度：
  - `markedForDeletion: Bool`
  - `skippedRecord: SkippedPhotoRecord?`
  - `timeMachineSelection: TimeMachineMonthProgress?`（可从 store 按月 query）
  - `smartCleanupProgress: SmartCleanupProgress?`（仅全相册模式）

### 3.3 Repositories / Stores

#### 3.3.1 PhotoLibraryRepository
**职责**
- 与 PhotoKit 交互、分页、相册筛选、库变化监听。
- 产出稳定的资产序列与元数据快照。

**对外 API（建议）**
- `start()` / `stop()`
- `currentFetchResult() -> PHFetchResult<PHAsset>?`
- `onAssetsLoaded: ([PHAsset]) -> Void`
- `onFetchResultUpdated: (PHFetchResult<PHAsset>) -> Void`
- `onLibraryChange: (PHFetchResultChangeDetails<PHAsset>) -> Void`
- `ensurePagingBuffer(displayedIndex: Int)`
- `visibleRangeDidChange(_ range: Range<Int>)`
- `fetchAssetIdentifiers(in collection) async -> Set<String>`（沿用现有逻辑）

**实现策略**
- 可直接封装/复用现有 `PhotoLoader`、`PhotoLibraryObserver`、`ImageCache`。

#### 3.3.2 PhotoAnalysisRepository
**职责**
- 统一分析缓存 schema、读写、失效、迁移。
- 提供增量分析需要的判定与合并能力。

**持久化**
- 初期继续使用 JSON（便于兼容旧缓存），路径放在 caches 或 documents：
  - 新文件名：`PhotoAnalysisCache_v2.json`
- schema version：`AnalysisResult.currentVersion`。

**对外 API（建议）**
- `loadSnapshot() -> [String: AnalysisResult]`
- `analysis(for assetId: String) -> AnalysisResult?`
- `needsAnalysis(for assetId: String, fileSize: Int, lastChangeDate: Date?) -> Bool`
- `merge(_ results: [String: AnalysisResult])`
- `remove(assetIds: [String])`
- `pruneMissing(keeping assetIds: Set<String>)`
- `dashboardSnapshot() -> DashboardSnapshot`（供首页统计使用）

**迁移策略**
- 读取旧 `PhotoAnalysisCacheStore`（documents/PhotoAnalysisCache.json）：
  - 若 `version == 1` 且 `fileSize` 匹配，转换为 `AnalysisResult` 写入新 cache。
- 读取旧 `ZeroLatencyCacheStore`（caches/PhotoAnalysisCache_v1.json）：
  - 只补齐缺失字段（fileSize、isScreenshot、sharpness→blurScore 近似、similarGroupId、lastAnalyzedAt 等）。
- 迁移是“按需 + 惰性”的：遇到未命中再迁移该条，避免冷启动全量 IO。

#### 3.3.3 PhotoUserStateRepository
**职责**
- 统一封装三类用户状态 store，避免 ViewModel 直接操作 UserDefaults。

**对外 API（建议）**
- Smart Cleanup
  - `loadSmartProgress() -> SmartCleanupProgress?`
  - `saveSmartProgress(_ progress: SmartCleanupProgress?)`
- TimeMachine
  - `monthProgress(year:month) -> TimeMachineMonthProgress?`
  - `allMonthProgresses() -> [TimeMachineMonthProgress]`
  - `setPhotoSelected(photoId:year:month:selected: Bool)`
  - `confirmPhoto(photoId:year:month)`
  - `removePhotoRecords(photoId:year:month)`
  - `resetAllTimeMachine()`
- Skipped
  - `skippedRecords() -> [SkippedPhotoRecord]`
  - `recordSkipped(photoId:source:)`
  - `markSkippedProcessed(ids:)`
  - `removeSkipped(ids:)`
  - `clearSkipped()`

### 3.4 Query / 派生服务

#### PhotoQueryService
**职责**
- 纯函数/可测试：输入 `PhotoRecord` 集合，输出 UI 所需派生集合。
- 所有规则从现有 ViewModel 拷贝，**语义保持一致**。

**输出（建议）**
- `allItems(records) -> [PhotoItem]`
- `similarItems(records) -> [PhotoItem]`
- `blurredItems(records) -> [PhotoItem]`
- `screenshotOrDocumentItems(records) -> [PhotoItem]`
- `largeItems(records) -> [PhotoItem]`
- `pendingDeletionItems(records) -> [PhotoItem]`
- `skippedItems(records) -> [PhotoItem]`
- `timeMachineYears(records) -> [Int]`
- `timeMachineMonthItems(records, year, month) -> [PhotoItem]`
- `monthAssetTotals(records) -> [String: Int]`
- `dashboardStats(records) -> DashboardStats`

**说明**
- 产出 `PhotoItem` 时，字段来自 record 的 metadata + analysis + userState。
- `PhotoItem` 保持现有结构，以保证 UI 无需改动。

### 3.5 数据编排层

#### PhotoDataController（actor 或 @MainActor class）
**职责**
- 作为数据层入口，管理 records 内存态、订阅 PhotoKit、调度分析、合并缓存与用户状态、发出派生结果。

**内部状态**
- `records: [String: PhotoRecord]`
- `orderedIds: [String]`（与 PhotoLoader 的加载顺序一致）
- `analysisQueue`（待分析 assetId 集合）

**对外 API（建议）**
- 生命周期
  - `start()` / `stop()`
- 快照/订阅
  - `snapshot() -> PhotoDataSnapshot`
  - `onSnapshotChange: (PhotoDataSnapshot) -> Void`
- 用户动作
  - `apply(action: PhotoUserAction)`  
    action 包含：markDeletion/keep/skip/toggleDeletion/resetProgress/confirmSkipped/...
- 删除后清理
  - `remove(assetIds:)`

**PhotoDataSnapshot**
- controller 向 ViewModel 输出的稳定结构，字段映射到现有 ViewModel `@Published`：
  - `items: [PhotoItem]`
  - `monthAssetTotals: [String: Int]`
  - `timeMachineSnapshots: [String: TimeMachineMonthProgress]`
  - `skippedPhotoRecords: [SkippedPhotoRecord]`
  - `smartCleanupProgress: SmartCleanupProgress?`
  - `dashboardStats: DashboardStats`
  - `isBootstrapping: Bool`

**关键数据流**
1. `PhotoLibraryRepository` 返回新 assets  
   → controller 构建/更新 records（先填 cached analysis + user state）  
   → 推送 snapshot（零延迟展示）  
   → 追加到 analysisQueue。
2. 后台分析 drain  
   → 生成 `AnalysisResult`  
   → `analysisRepo.merge` 持久化  
   → 更新 records  
   → 重新派生并推送 snapshot。
3. 用户动作  
   → `userStateRepo` 落盘  
   → 更新 records.userState  
   → 推送 snapshot。

**并发模型**
- PhotoDataController 统一“写路径”，避免跨线程直接写 ViewModel 数据。
- ViewModel 只在主线程接收 snapshot 并赋值。

## 4. 与现有 ViewModels 的对接

### 4.1 保持 UI API 不变
`PhotoCleanupViewModel` 保留全部现有 `@Published` 字段和 public 方法签名（例如 `showCleaner`, `performDeletion` 等）。

### 4.2 改造方式（内部）
- ViewModel 持有 `PhotoDataController`：
  - init 中创建并绑定 `onSnapshotChange`。
  - `onSnapshotChange` 回调里只做字段赋值（items/sessionItems/monthTotals/...）。
- 原有内部私有函数逐步下沉：
  - `ingestAssets`, `analyzeAllItemsInBackground`, `applyCachedEntry`,
    `persistSelectionState`, `logSkippedPhoto`, `refreshTimeMachineSnapshots` 等。

## 5. 分步实施计划

1. **Step A：抽取纯派生逻辑**
   - 新增 `PhotoQueryService`，把过滤/排序/统计规则从 ViewModel 拷贝过去。
   - ViewModel 仍保留旧流程，但派生改为调用 service。
2. **Step B：统一用户状态仓库**
   - 新增 `PhotoUserStateRepository` 包装现有三个 store。
   - ViewModel 改为只调用仓库 API。
3. **Step C：统一分析仓库并迁移旧缓存**
   - 新增 `PhotoAnalysisRepository`（读旧写新，惰性迁移）。
   - ViewModel 读写缓存逻辑迁移到仓库。
4. **Step D：引入 PhotoDataController**
   - 让 controller 驱动加载与分析。
   - ViewModel 只订阅 snapshot。
5. **Step E：清理旧代码路径**
   - 删除冗余缓存/分析调度/派生函数。

每一步都保证：
- UI 不变；
- 同一筛选/月份/统计重构前后结果一致（人工/断言比对）。

## 6. 风险与回归点
- **缓存一致性**：迁移期需确保新旧缓存命中策略完全等价（版本、fileSize、modificationDate）。
- **相似分组稳定性**：分组算法不变，尤其是时间窗口与阈值（保持现有规则）。
- **时光机可见规则**：deferred/markedForDeletion/selectedAlbum 等过滤不能变。
- **性能**：冷启动与滚动分析不能退化；惰性迁移避免全量 IO。

## 7. 测试策略
- 单测（优先）：
  - `PhotoQueryService`：给定 records，断言各派生集合与统计值。
  - `PhotoAnalysisRepository`：旧缓存读取/转换/命中/失效。
  - `PhotoUserStateRepository`：set/confirm/remove/reset 的正确性。
- 回归手测：
  - 大库启动、滚动加载、后台分析完成前后列表一致。
  - 各模块筛选数量与重构前一致。
  - 删除/跳过/重置的边界场景。

---

如果你确认该设计，我下一步会从 Step A 开始落代码，并在每个 step 结束后与你确认结果与行为一致性。  
