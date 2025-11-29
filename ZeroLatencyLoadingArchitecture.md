# 零延迟相册加载蓝图

本文档描述了一套满足 Photos 框架最佳实践、并在感知上实现“接近零延迟”相册加载体验的启动与后台处理方案。

## 目标

- 启动阶段主线程耗时控制在 50ms 内，完全依赖缓存仪表盘数据秒开首页。
- 首次只拉取最近约 100 个资源，之后按 200 张为一批分页，保证滚动顺滑。
- Vision 特征提取、模糊度检测、文件体积排序等重任务全部在后台队列执行，并支持取消。
- 所有分析结果持久化到版本化 JSON 缓存，实现随开随用的状态恢复。

## 启动流程（SwiftUI + Photos）

1. **缓存预热**  
   `PhotoAnalysisCacheStore` 读取缓存目录下的 `PhotoAnalysisCache.json`，结构包含仪表盘指标、最近缩略图的元数据、以及每个资产的分析条目。若文件缺失或版本不匹配，`CacheStore` 返回一个“空但合法”的快照，同时标记 `.needsBootstrap` 以便后续补建。
2. **立即渲染 UI**  
   `ZeroLatencyPhotoViewModel` 将缓存得到的 `DashboardSnapshot` 发布给 SwiftUI，首页即可展示照片总数、按月统计、相似分组及大文件列表，无需等待 Photos 授权。
3. **权限与索引引导**  
   `PermissionsManager` 请求读授权；授权通过后 `PhotoLoader` 获取按创建时间倒序的 `PHFetchResult<PHAsset>`，此阶段只读取元数据。
4. **首批资源**  
   `PhotoLoader` 在后台把最新 100 个资产转换为轻量 `AssetItem`，同时调用 `ImageCache` 为索引区间 `0..<150` 预取缩略图，并把结果推送给网格视图。
5. **后台分析**  
   首批数据就绪后，`AnalysisManager` 找出缓存缺失的 asset，按 50 张为一批开始后台任务。每批完成都会更新缓存 actor，落盘并通知 ViewModel 刷新。

## 组件

- `PhotoLoader`：维护分页状态，暴露 `@Published var items: [AssetItem]`，并与 `ImageCache` 协作完成可视范围预取。
- `ImageCache`：对 `PHCachingImageManager` 的封装，提供 `startCaching(indices:)`、`stopCaching(indices:)`、`requestThumbnail(asset:targetSize:)` 等接口。
- `PhotoAnalysisCacheStore`：负责 JSON 读写、增量合并、生成仪表盘快照的 `actor`。
- `AnalysisManager`：持有串行 `Task` 队列，按 50 张切片，执行 Vision 特征 + 模糊评分 + 文件大小查询，并通过 `CacheStore` 写入。
- `PermissionsManager`：统一处理 `PHPhotoLibrary` 授权及状态监听。
- `PhotoLibraryObserver`：实现 `PHPhotoLibraryChangeObserver`，计算新增/删除范围，驱动 `PhotoLoader` 与 `AnalysisManager` 做增量更新。

## JSON 缓存结构

```json
{
  "cacheVersion": 1,
  "lastAnalysisDate": "2024-05-26T11:04:00Z",
  "totalAssetCount": 38452,
  "monthlyBuckets": {
    "2024-05": 812,
    "2024-04": 640
  },
  "recentThumbnailIds": ["4E93...","7B02...", "..."],
  "similarGroupSummaries": [
    { "groupId": "grp-1", "count": 14, "coverId": "4E93..." }
  ],
  "largeFiles": [
    { "assetId": "9A01...", "fileSize": 12873432 }
  ],
  "entries": {
    "4E93...": {
      "assetId": "4E93...",
      "fileSize": 4234811,
      "isScreenshot": false,
      "sharpness": 0.92,
      "featureGroupId": "grp-1",
      "lastAnalyzedAt": "2024-05-26T11:04:00Z"
    }
  }
}
```

## 推荐缓存与数据 Schema（PhotoAnalysisCache_v1.json）

缓存文件采用版本号命名：`PhotoAnalysisCache_v1.json`，内容与写盘策略如下，可直接作为工程规范。

```json
{
  "schemaVersion": 1,
  "lastUpdated": "2025-11-30T12:00:00Z",
  "totalCount": 12345,
  "recentPreview": [
    { "id": "assetLocalId1", "thumb": "", "createdAt": "2025-11-29T10:00:00Z" }
  ],
  "monthlyCounts": [
    { "year": 2025, "month": 11, "count": 240 }
  ],
  "assets": {
    "assetLocalId1": {
      "fileSize": 2345678,
      "isScreenshot": false,
      "isVideo": false,
      "sharpness": 72.3,
      "similarGroupId": 12,
      "featureHash": "base64-or-hex",
      "lastAnalyzedAt": "2025-11-29T10:00:00Z"
    }
  },
  "topLargeFiles": ["assetLocalIdX", "assetLocalIdY"],
  "analysisMeta": {
    "lastSimilarityRun": "2025-11-29T10:00:00Z",
    "version": "1.0.0"
  }
}
```

实现要点：

- **仅存储元数据与分析结果**，不写入任何缩略图或原图数据，真正的图像渲染依赖 `PHAsset/PHCachingImageManager`。
- **统一以 `localIdentifier` 作为 key**，确保与 Photos 框架的资产引用一致，可直接定位增量变更。
- **原子写入**：`CacheStore` 先将 JSON 写入临时文件（`PhotoAnalysisCache_v1.json.tmp`），成功后再 `FileManager.default.replaceItemAt` 或 `moveItem` 到正式路径，避免并发或崩溃导致的损坏。
- **版本管理**：通过 `schemaVersion` 字段控制迁移；当检测到版本不匹配或文件损坏时，自动迁移或重建空缓存，并触发后台重新分析。

## 用户感知与 UI 建议

- **启动立即显示**：冷启动阶段只展示 App Logo、缓存统计与灰色骨架网格，确保“秒开”观感。
- **首屏缩略图策略**：若缓存存在 `recentPreview` 数据，优先渲染其 metadata + 占位图；缓存缺失则直接显示骨架，并在后台立即请求首屏缩略图。
- **顶部分析状态标签**：在导航栏或首页顶部显示“分析中…”小标签，实时反映后台进度，但不阻塞任何交互。
- **滚动预取**：`ScrollView`/`CollectionView` 接近底部（例如剩余 <80 张）时调用 `PhotoLoader.fetchPage()`，并同步触发 `ImageManagerWrapper.startCaching` 扩大预取区间。
- **平滑注入数据**：后台分析完成后，只对受影响的 Cell/Section 做 diff 更新，配合 opacity/scale 动画插入，避免整屏重建造成闪烁。

## 实施注意事项（要点清单）

- 不在主线程执行任何图像解码或 Vision 分析，所有重任务放在后台并通过 `Task`/`DispatchQueue` 控制。
- 后台分析使用批处理 + backoff，例如一次处理 50 张，若检测到系统压力或任务堆积则降低并发或增加间隔。
- 写缓存必须是原子操作，并结合 `schemaVersion` 与并发锁（如 `actor` 或串行队列）防止数据竞态。
- 预取范围统一交由 `PHCachingImageManager.startCaching/stopCaching` 管理，确保随滚动动态调整。
- 注册 `PHPhotoLibraryChangeObserver`，在变更回调中计算 delta，驱动 `PhotoLoader` 和 `AnalysisManager` 做增量更新。
- 当用户进入特定功能（如相似照片页）时，如果缓存有现成数据立刻展示；否则立即启动增量分析，并分批回流结果到 UI。

## Swift 实现概览

该方案已以可运行代码形式落地在 `PhotoTidy/ZeroLatency` 目录：

- `ZeroLatencyPhotoViewModel.swift`：组合 `PermissionsManager`、`PhotoLoader`、`AnalysisManager`、`PhotoAnalysisCacheStore`，对外暴露 `DashboardSnapshot` 与分页 `items`。
- `PhotoAnalysisCacheStore.swift`：版本化 JSON 缓存读写；`PhotoAnalysisCache_v1.json` 采用原子写、`schemaVersion` 迁移策略。
- `PhotoLoader.swift` + `ImageCache.swift`：负责索引 + 分页加载 + 滚动预取，并将首屏 100 张与后续 200 张批次按需注入 UI。
- `AnalysisManager.swift`：使用 Vision FeaturePrint + Blur 检测在后台队列分批处理，每批 50 张，带 backoff 与缓存合并。
- `ZeroLatencyRootView.swift`：新的 SwiftUI 入口，冷启动即展示 Logo + 缓存统计 + 骨架网格，滚动过程中动态触发分页、预取与分析状态动画。
- `PhotoCleanupViewModel`：保留原有 Dashboard/清理功能不变，但内部已接入 `PhotoLoader` 的分页加载与缓存逻辑，实现“页面不变、加载零延迟”的效果。

要体验零延迟架构，可在 `FeatureToggles.useZeroLatencyArchitectureDemo` 设为 `true`（默认已开启），`PhotoTidyApp` 会直接启动 `ZeroLatencyRootView`，并依托上述组件完成“缓存秒开 → 懒加载 → 后台分析”的完整链路。

## 增量更新流程

1. 读取缓存 → UI 立即展示缓存仪表盘。
2. `PhotoLoader` 拉取 `PHFetchResult`，与缓存比对得出 `pendingAssetIds`。
3. `AnalysisManager.scheduleIncrementalWork(ids:)` 以 50 张为单位处理待分析资产。每个批次：
   - 在后台队列请求 Fast Format 图像数据；
   - 运行 Vision `VNGenerateImageFeaturePrintRequest` 与模糊评分；
   - 通过 `PHAssetResource` 获取文件大小并判断是否为截图；
   - 生成新的 `PhotoAnalysisCacheEntry` 交给 `CacheStore`。
4. `CacheStore` 合并条目（不影响未变资产），更新仪表盘聚合数据，使用 `write(to:options:.atomic)` 原子写盘，并广播 `Notification.Name.cacheSnapshotChanged`。
5. ViewModel 监听通知，刷新 `@Published` 快照，SwiftUI 即时重渲染且不阻塞交互。

## 故障与回退

- 缓存缺失或损坏：展示占位 UI，同时后台执行 `PhotoLoader.bootstrapIndex()` 构建轻量索引。
- 授权被拒：首页维持缓存/占位状态，并提示用户在设置中开启权限。
- 分析过程中收到图库变更：取消当前批次，基于最新 `analysisGeneration` 重新调度，确保数据正确。

该蓝图由仓库中的 Swift 实现（核心入口 `PhotoTidy/ZeroLatency/ZeroLatencyRootView.swift`）提供完整示例，可直接复用或按需扩展。
