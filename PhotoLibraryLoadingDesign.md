# PhotoTidy 相册加载优化方案

该文档总结本次相册加载链路的实现方式，便于后续维护或扩展。以下所述代码均位于仓库中的 `PhotoTidy` 目录。

## 启动阶段（轻量索引）

1. **PhotoLibraryService**（`Services/PhotoLibraryService.swift`）
   - 仅依赖 `PHAsset.fetchAssets` 获取 `PHFetchResult` 引用，避免在启动时遍历所有 `PHAsset`。
   - 读取前 `defaultPageSize`（默认 160）张照片构建 `PhotoItem`，填充首屏。
   - 顺带扫描 `PHAssetCollection`，生成 `AlbumIndexSummary`（`Models/AlbumIndexSummary.swift`），包含 `estimatedCount`、日期范围与首图标识，供首页/设置等地方快速展示统计信息。
2. **PhotoCleanupViewModel.loadAssets**（`ViewModels/PhotoCleanupViewModel.swift:248` 起）
   - 启动时只注入首批 `PhotoItem`，同时恢复本地选择状态与分析缓存。
   - 初始化分页状态 `PagingState`（总数/已加载/是否在拉取）。
   - 立即触发一次分析（仅针对当前已加载的资源），保证首屏可以快速得出模糊/相似统计。

## 分页、懒加载与后台预取

1. **用户驱动的按需加载**
   - `AssetThumbnailView` 新增 `onDisplay` 回调；`AlbumGridView` 在 cell `onAppear` 时调用 `PhotoCleanupViewModel.notifyAssetDisplayed`，符号引用位于 `Views/AlbumGridView.swift:34`。
   - ViewModel 内部方法 `ensurePagingBuffer(forIndex:)` 判断“距列表底部不足 60 张”时触发 `loadNextPage(trigger: .userScrolling)`，仅加载必要的数据。
2. **后台预取**
   - `scheduleBackgroundPrefetchIfNeeded` 会在 UI 稳定后延迟 1 秒启动一个 utility 队列循环（`drainBackgroundPrefetchLoop`），按照页大小 + 350ms 间隔温和拉取剩余数据。
   - 后台预取过程中若检测到新的用户触发分页，会让用户请求优先；预取完成或被 `loadAssets` 重置时自动取消。
3. **会话队列的增量维护**
   - `appendSessionItems(with:)` 使用当前过滤条件将新增照片纳入 `sessionItems`，避免频繁重建与 `currentIndex` 回滚。

## PHCachingImageManager 预加载

1. `PhotoCleanupViewModel` 维护 `cachingRange`，窗口宽度（默认 90）围绕当前可见索引扩张。
2. `updateCachingWindow(around:)` 比较新旧范围，仅对变化的资产调用 `startCachingImages` / `stopCachingImages`。
3. 目标尺寸 `220 * UIScreen.scale`，`PHImageRequestOptions` 设为 `opportunistic + fast`，兼顾首帧速度与后续清晰度。
4. 当重新加载或销毁 VM 时通过 `stopCachingIfNeeded` 彻底释放缓存。

## 分析任务与缓存协作

1. **分析调度**
   - 每次调用 `analyzeAllItemsInBackground` 会生成自增 token（`analysisGeneration`），保证旧任务完成后不会覆盖新任务结果或误把 `isAnalyzing` 设为 false。
   - 动态分页期间只分析已加载的子集；当后台预取遍历完整库后，再次触发全量分析，确保最终准确度。
2. **增量合并**
   - 分析结果不再直接替换 `items`，而是以 `id -> PhotoItem` map 方式合并到最新数组，仅更新相关字段。
   - 分析缓存（`PhotoAnalysisCacheStore`）会在所有页加载完毕后再做一次 `pruneMissingEntries`，避免额外的完全遍历。

## 生命周期示意

```
App Launch
 └─ requestAuthorization() ✓
    └─ PhotoLibraryService.bootstrap()  → 初始 PhotoItem + AlbumIndexSummary
       └─ ViewModel 显示首屏 / 启动首轮分析
          └─ scheduleBackgroundPrefetch() → 后台温和拉取剩余页
             ├─ 用户滚动 → notifyAssetDisplayed → loadNextPage(用户) + updateCachingWindow
             ├─ 后台预取 → loadNextPage(后台) + 结果缓存
             └─ 所有页就绪 → pruneMissingEntries + analyzeAllItemsInBackground(全量)
```

### 二次启动

1. 读取缓存的 `AlbumIndexSummary` + 已分析结果，首屏延迟基本为 0。
2. 仍按引导流程执行一次轻量 bootstrap（以捕捉授权变化或新照片），预取与分析逻辑与首次一致。

## 接入/扩展建议

1. 新增列表或 Section 时，只需在 cell `onAppear` 中调用 `notifyAssetDisplayed` 即可复用分页与缓存逻辑。
2. 若需要更激进的懒加载，可以调低 `PhotoLibraryService.defaultPageSize` 或调整 `ensurePagingBuffer` 阈值。
3. 后续如需展示 `AlbumIndexSummary`，可以直接订阅 `PhotoCleanupViewModel.albumSummaries`。
4. 若要扩展分析任务（如“时光机扫描”），建议沿用 `analysisGeneration` 模式，避免并发结果互相覆盖。

本方案确保了：

- 启动阶段只加载必需元数据与首屏缩略图，避免卡顿。
- 通过懒加载与后台预取分散 CPU/内存压力，同时保持扫描的准确性。
- `PHCachingImageManager` 搭配窗口策略提升滚动顺滑度。
- 重任务在后台异步执行并缓存，UI 采用占位视图减少感知延迟。
