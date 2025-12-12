# PhotoTidy 首装全量索引 + 后续增量 Diff 设计

本设计对应我们当前重构计划的第 2 步：在不改 UI 的前提下，让应用**首装/首授权时后台全量扫描并持久化索引**；后续进入时先用索引秒级恢复统计/状态，再后台与 PhotoKit 做 diff，仅处理增量变化，从而显著提升启动与二次进入体验。

## 目标

- **启动体验**：二次进入时 Dashboard/时光机/月统计立即可用（无需等待全库枚举），加载更丝滑。
- **分析成本**：只为新增/变更的资源做分析与缓存更新，避免重复跑全量分析。
- **正确性**：在可控成本内保证删改增能被检测到；极端情况保留安全回退。
- **约束**：不调整任何 UI/View；不修改公开 `@Published` 字段名/语义与对外方法签名。

## 现状与瓶颈

当前每次拿到 `PHFetchResult` 后，`PhotoDataController.handleFetchResultUpdate` 会：

1. **全量枚举**所有 asset 计算 `monthAssetTotals`。
2. 全量枚举 id 集合用于 prune 缓存缺失项。

即使这些任务在后台线程，也会造成：

- 二次进入时统计仍需等待后台枚举完成才逐步出现（体感“慢热”）。
- 若全库很大（>3~5 万张），后台枚举也会占用较多 CPU/内存，影响前台滚动与分析。

## 总体方案

### 核心思想

1. **首装/首授权**：后台全量扫描一次，生成本地索引文件 `LibraryIndex_v1.json`。
2. **后续启动**：
   - 先读取索引，立即填充 `monthAssetTotals/totalCount`，发布快照，让 UI 秒开。
   - 再后台取最新 `PHFetchResult`，通过“轻量校验 + 需要时全量 diff”检测增删改：
     - 若无变化或变化很小：只做必要的增量更新。
     - 若变化较大或校验不通过：后台全量 diff 并更新索引。

### 索引保存位置

- 放在 `Documents/LibraryIndex_v1.json`：
  - 统计/索引是用户级持久状态，希望稳定保留。
  - 允许 iOS 清理缓存时不丢失。
- 文件损坏/版本不匹配时自动丢弃并重建。

## 索引 Schema（v1）

```json
{
  "schemaVersion": 1,
  "lastIndexedAt": "2025-12-12T12:00:00Z",
  "totalCount": 12345,
  "monthCounts": {
    "2025-12": 321,
    "2025-11": 456
  },
  "assetIdsSorted": [
    "A1", "A2", "A3"
  ],
  "headSample": ["A1", "A2", "..."], 
  "tailSample": ["Z9", "Z8", "..."]
}
```

字段说明：

- `assetIdsSorted`：按 `creationDate desc` 排序的全库 id 列表（来源同 `PHFetchOptions` 排序）。
- `monthCounts`：key 为 `"year-month"`，用于时光机月统计与 Dashboard。
- `headSample/tailSample`：各取 N=32 个头/尾样本，用于启动时的**轻量变化检测**。
- `lastIndexedAt`：用于“长期未校验则后台全量 diff”的保底策略。

> v1 不记录相册维度的 asset 列表，避免文件膨胀；后续可扩展 `albums` 字段做相册过滤加速。

## 启动流程

### 1. 首装/无索引

1. `PhotoLoader.start()` 生成 `PHFetchResult` 并回调 `handleFetchResultUpdate`。
2. `PhotoDataController` 发现索引缺失：
   - 立即用 `fetchResult.count` 填充 `totalCount`（若 monthCounts 为空则暂为 0/placeholder）。
   - 启动后台任务：
     - 全量枚举 `fetchResult` → 生成 `assetIdsSorted + monthCounts`。
     - 持久化索引。
     - 回到主线程更新 `monthAssetTotals` 并发布快照。
3. 分页加载/分析调度不受影响。

### 2. 二次进入/有索引

1. `PhotoDataController.init` 先读取索引：
   - 直接设置 `monthAssetTotals = index.monthCounts`，发布一次快照（UI 秒级有数据）。
2. 当 `handleFetchResultUpdate(fetchResult)` 到来：
   - **轻量校验**（同步/小成本）：
     - 读取 `fetchResult.count` 与 `index.totalCount` 比较。
     - 枚举 fetchResult 的头 N 与尾 N ids 与 `headSample/tailSample` 比较。
   - 若 `count` 或 sample 不一致 → 标记 `needsFullDiff = true`。
   - 若一致且 `now - lastIndexedAt < 6h` → 跳过全量 diff，仅做 prune 轻更新。
   - 其余情况后台执行全量 diff（见下一节）。

## 全量 diff（后台）

当需要全量 diff 时：

1. 后台枚举当前 `fetchResult`：
   - 构建 `currentIdsSorted`（数组）。
   - 统计 `currentMonthCounts`。
2. 计算：
   - `added = currentIdsSet - indexIdsSet`
   - `removed = indexIdsSet - currentIdsSet`
3. 更新索引：
   - 写入新 `assetIdsSorted/monthCounts/totalCount/headSample/tailSample/lastIndexedAt`。
4. 触发数据层增量：
   - `analysisCache.pruneMissingEntries(keeping: currentIdsSet)`。
   - 若有 `added`：
     - 用 `PHAsset.fetchAssets(withLocalIdentifiers:)` 拉回新增 assets，
       交给 `handleLoadedAssets` 入队分析（normal 优先级）。
5. 主线程更新 `monthAssetTotals` 并发布快照。

## 运行期增量更新（PhotoKit changeDetails）

应用运行期间：

- `PhotoLoader.applyChangeDetails(details)` 已维持分页顺序与 preheat。
- `PhotoDataController.applyLibraryChange(details)` 做已加载前缀 diff。

新增：在 `applyLibraryChange` 内部（后台）同步更新索引 store：

1. 若 `details.hasIncrementalChanges`：
   - 读取 `fetchResultAfterChanges` 的 `count`。
   - 通过 `details.insertedIndexes/removedIndexes/changedIndexes` 更新：
     - `assetIdsSorted`（按 index 插入/删除）。
     - `monthCounts`（依据 insert/remove 的月份 key 递增/递减）。
   - 更新 sample 与 `lastIndexedAt`。
2. 若非增量 → 标记索引失效，等下一次 `handleFetchResultUpdate` 做全量重建。

这样可以让索引在运行期保持新鲜，减少下一次启动的 full diff 概率。

## 回退与容错

- 索引文件：
  - JSON decode 失败 / `schemaVersion` 不匹配 → 视为无索引，走首装重建逻辑。
- 变化检测漏检风险：
  - 若用户在中间位置发生“等量增删导致 count 不变，且头尾 sample 未变”，可能跳过一次 full diff。
  - 保底：当 `now - lastIndexedAt >= 6h` 时仍会后台 full diff。
- 权限变化（limited → full / selection 改变）：
  - count/sample 会变化，触发 full diff，索引自动修正。

## 性能预期

- 二次进入时：
  - `PhotoDataController.init` 读取 JSON 并发布快照：毫秒级。
  - UI 立即显示总数/月统计/时光机分组，不再等待后台枚举。
- 后台 diff：
  - 仅在需要时做全量枚举；而且不阻塞主线程。
  - 新增/删除会被精确计算，只为新增项入队分析。

## 代码落地拆分（小步可回滚）

1. 新增索引模型与 store
   - `PhotoTidy/Services/LibraryIndex.swift`
   - `PhotoTidy/Services/LibraryIndexStore.swift`（actor，load/save/diff/applyIncremental）
2. `PhotoDataContainer` 注入 `LibraryIndexStore`
3. `PhotoDataController`
   - init 读索引并初始化 `monthAssetTotals`
   - `handleFetchResultUpdate` 改为走“轻量校验 + 后台 diff”，移除每次全量枚举
   - `applyLibraryChange` 补索引增量应用
4. 本地回归：全相册 / 时光机 / 大文件 / 模糊 / 截图文档 / 待确认 / 待删除

## 后续可扩展

- `albums` 维度索引（加速相册过滤）：
  - 可选存 `collectionId -> [assetIds]` 或 `collectionId -> bloom filter`。
- 索引压缩：
  - 对 `assetIdsSorted` 做 chunk + zlib，进一步减少体积与 IO。

