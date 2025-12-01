# PhotoTidy 零延迟加载落地方案

本文档对应仓库中最新的实现，说明全局“零延迟”数据架构、模块化仓库、缓存与 ViewModel 调整方式，方便后续维护与扩展。

## 1. 整体架构

```
SwiftUI View → ViewModel (PhotoCleanup / Timeline / Modules)
    ↘ 只读轻量快照：MetadataRepository + MetadataCacheStore
    ↘ 实际资源：PhotoRepository + ImagePipeline + PhotoKit
    ↘ 状态缓存：PhotoAnalysisCacheStore / TimeMachineProgressStore / SkippedPhotoStore
        ↘ BackgroundJobScheduler / TaskPool → 后台增量任务
```

- **首帧阶段**只访问 `MetadataRepository`，读取 `identifier / creationDate / pixelSize / estimatedAssetByteCount` 等轻量字段，缓存由 `MetadataCacheStore` (actor) 持久化。
- **真实资源**只在用户进入功能页时通过 `PhotoRepository` 分批拉取；`ImagePipeline` 负责 `PHCachingImageManager` 的窗口预加载、Memory + Disk cache 与任务取消。
- **后台任务**统一交给 `BackgroundJobScheduler` (模糊 / 相似 / 元数据刷新)，避免阻塞主线程。

## 2. 数据层设计

| 组件 | 说明 | 关键文件 |
| --- | --- | --- |
| `MetadataRepository` | 读取 PhotoKit 元数据、合并 `PhotoAnalysisCacheStore` 结果，输出 `MetadataSnapshot`。缓存中新增 `monthMomentIdentifiers` 字段，映射 `year-month` → `PHAssetCollection`（Moment）集合，确保与系统相册“时光”一致。 | `PhotoTidy/DataLayer/Metadata/MetadataRepository.swift` |
| `MetadataCacheStore` | actor, JSON 原子写，字段：`totalCount`、`monthTotals`、`CategoryCounters`、`DeviceStorageUsage`。 | `PhotoTidy/DataLayer/Metadata/MetadataCacheStore.swift` |
| `PhotoRepository` | actor，负责按 Scope（全部/月度/相册）维护 `PHFetchResult`，提供分页 `fetchNextBatch`、`prefetchMonth`、`assets(for:)`。 | `PhotoTidy/DataLayer/PhotoRepository.swift` |
| `ImagePipeline` | 包装 `PHCachingImageManager`，提供 `requestImage`、`prefetch/stopPrefetching`、`cancelAll`，内部联合 `NSCache` 与 `ImageDiskCache`。 | `PhotoTidy/DataLayer/ImagePipeline` |
| `TaskPool` | actor，管理各 Scope 的 `Task<Void, Never>`，ViewModel 离场即取消。 | `PhotoTidy/DataLayer/TaskPool.swift` |
| `BackgroundJobScheduler` | actor，描述 Job → Task 映射，用于模糊/相似/缓存刷新。 | `PhotoTidy/DataLayer/BackgroundJobScheduler.swift` |

## 3. 各功能模块零延迟策略

- **首页 / Dashboard**：首帧直接订阅 `metadataSnapshot` 展示总数、月份、类别计数；真实 `PhotoItem` 仅在进入 Cleaner / Detail 时加载。
- **全相册清理**：`showCleaner` 首次调用 `ensureRealAssetPipeline()`，唤醒分页加载；`prefetchMonthAssetsIfNeeded` 在零延迟模式下改用 `PhotoRepository + ImagePipeline` 异步预热下一月份，支持任务取消。
- **相似图片**：零首帧由 `metadataSnapshot.categoryCounters.similar` 提供数量。展开时复用 `PhotoRepository` 分页，`BackgroundJobScheduler` 在后台跑 Vision。
- **大文件**：`MetadataRepository` 只依赖 `estimatedAssetByteCount` 统计；真实文件仅在需要预览/操作时取。
- **模糊检测**：重任务挂在 `BackgroundJobScheduler` 的 `.similarity` 作业里，通过 `scheduleBackgroundAnalysisIfNeeded` 分批执行，可随 TaskPool 取消。
- **截图/文档**：首屏使用 `MetadataSnapshot` 的 screenshot/document 计数，进入列表时才加载真实 `PhotoItem`。
- **时光机**：`MetadataRepository` 额外缓存 `monthMomentIdentifiers`，因此 TimeMachine 卡片能直接复用系统 Moment（与苹果相册一致）。进入月份优先通过 `PhotoRepository.fetchAssets(forMomentIdentifiers:)` 取真实图片，只有缺失 moment 时才回退到 `creationDate` 谓词。`TaskPool` 负责取消未完成的月份预取；在旧 UI 中点击月份时会调用零延迟 Detail VM 把 asset id 注入 `PhotoCleanupViewModel.prepareSession`，从而沿用原有「滑动跳过/确认/待删」交互但无加载延迟。

## 4. ViewModel 调整

- `PhotoCleanupViewModel` 新增依赖：
  - `metadataRepository` → 初始化时调用 `setupMetadataPipeline()` 并通过 Combine 更新 `monthAssetTotals`、`deviceStorageUsage`。
  - `photoRepository` / `imagePipeline` / `taskPool` / `backgroundScheduler` → 负责真实资源、缓存、后台任务。
  - `FeatureToggles.enableZeroLatencyPipeline` + `lazyLoadPhotoSessions` 决定是否在启动时加载真实照片。
- `showCleaner / showDetail / showCleaner(forMonth:)` 中调用 `ensureRealAssetPipeline()`，确保真实资源按需加载。
- `TimeMachineTimelineViewModel` 仍监听 `monthAssetTotals`，但这些值已由 metadata 缓存即时提供。

## 5. PHCachingImageManager 优化

- `PhotoLoader` 继续负责分页，但当零延迟模式启用时只在真正需要时启动。
- `ImagePipeline` 将 `targetSize` × `UIScreen.scale` 后统一请求，并通过 `ImageDiskCache` (LRU) + `NSCache` 管理缓存。
- `prefetchMonthAssetsIfNeeded` 优先基于 `MetadataSnapshot.monthMomentIdentifiers` 调用 `PhotoRepository.fetchAssets(forMomentIdentifiers:)`，确保与系统“时光”一致；若该月份尚未生成 moment，则回退到 `prefetchMonth`。之后交给 `ImagePipeline.prefetch` 并注册到 `TaskPool`，可按月份取消。零延迟 Detail ViewModel 也会复用同一套逻辑，将解析出的 asset id 注入 `PhotoCleanupViewModel.prepareSession`，旧版 Cleaner 即可直接消费。

## 6. 分批加载 / 可取消代码示例

```swift
let query = PhotoQuery(scope: .month(year: 2024, month: 5))
Task {
    let batch = await photoRepository.fetchNextBatch(query: query, batchSize: 20)
    await MainActor.run { self.sessionItems.append(contentsOf: batch.map(PhotoItem.init)) }
}

let prefetchTask = Task<Void, Never> { [weak self] in
    guard let self else { return }
    let assets = await self.photoRepository.prefetchMonth(year: 2023, month: 11, limit: 200)
    self.imagePipeline.prefetch(assets.map(\.asset), targetSize: CGSize(width: 280, height: 280))
}
await taskPool.insert(prefetchTask, scope: .prefetch)     // 离开页面时 TaskPool 自动 cancel
```

## 7. 流程：一级元数据 → 二级真实照片

1. **启动 / 回前台**：`PhotoCleanupViewModel.ensureAssetsPrepared()` 调用 `metadataRepository.bootstrapIfNeeded()`；UI 即刻订阅 `metadataSnapshot` 渲染。
2. **后台刷新**：`MetadataRepository` 在 `DispatchQueue` 中遍历 `PHFetchResult`，更新 `MetadataCacheStore` 并广播。
3. **进入功能页**：调用 `ensureRealAssetPipeline()`，触发 `PhotoLoader` + `PhotoRepository.fetchNextBatch`，真实 `PhotoItem` 进入内存。
4. **滚动/分页**：`PhotoRepository` 记录 `pagingState`，`ImagePipeline` 根据可见区更新缓存窗口，可随 `TaskPool` 或页面销毁取消。
5. **分析/预处理**：`BackgroundJobScheduler` 在 `.similarity` Job 中运行 Vision/模糊检测，结果写入 `PhotoAnalysisCacheStore`，下一次 metadata 快照即复用。

## 8. 代码改动指南

- `PhotoCleanupViewModel.swift`
  - 新增 `metadataSnapshot`、`metadataRepository`、`photoRepository` 等字段；`setupMetadataPipeline()` 负责订阅。
  - `ensureAssetsPrepared`/`updateAuthorizationStatus`/`requestAuthorization` 同步 metadata 引导，必要时再启动真实分页。
  - `prefetchMonthAssetsIfNeeded` 改用 `PhotoRepository + ImagePipeline + TaskPool`，支持取消。
  - `scheduleBackgroundAnalysisIfNeeded` 接入 `BackgroundJobScheduler`，避免主线程阻塞。
  - `prepareSession(with:month:)` 支持零延迟时光机将按月解析出的 `PHAsset` 列注入旧 Cleaner，会构建 `PhotoItem`、恢复标记状态并直接打开原有 UI。
- `FeatureToggles.swift`：新增 `enableZeroLatencyPipeline`、`lazyLoadPhotoSessions` 控制入口。
- 新文件：
  - `PhotoTidy/Models/DeviceStorageUsage.swift`
  - `PhotoTidy/DataLayer/Metadata/*`
  - `PhotoTidy/DataLayer/PhotoRepository.swift`
  - `PhotoTidy/DataLayer/ImagePipeline/*`
  - `PhotoTidy/DataLayer/TaskPool.swift`
  - `PhotoTidy/DataLayer/BackgroundJobScheduler.swift`

## 9. 性能优化清单

- **60 FPS**：`ImagePipeline` 的 memory/disk cache + `PHCachingImageManager` 窗口提升滚动流畅度；`TaskPool` 保证离场即取消重任务。
- **启动速度**：首帧只读 `MetadataCacheStore`（JSON 解码 < 50ms），`FeatureToggles.lazyLoadPhotoSessions` 阻止不必要的真实资源加载。
- **后台任务**：`BackgroundJobScheduler` 将 Vision/模糊分析搬到 utility task，默认批量 50 张，可随 `TaskPool` 暂停。
- **内存占用**：`ImagePipeline` 默认 120MB `NSCache` + 200MB `ImageDiskCache`，离开页面或收到内存警告时可统一 `cancelAll`。
- **时光机数据**：`monthAssetTotals` 直接由 metadata 缓存提供，仅在 PhotoKit 有变更时重新扫描，从而在大库中依旧“秒开”。
