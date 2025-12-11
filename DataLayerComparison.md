# 数据层对比（main vs v1.0）

## 核心区别速览
- **加载管线**：  
  - main：`PhotoSessionManager` 以小批次（全库/筛选 10 张，月份 18 张）增量加载并可窗口裁剪，优先预热缩略图 `PhotoTidy/DataLayer/PhotoSession/PhotoSessionManager.swift:26-113`。  
  - v1.0：`LibraryStore` 直接用 `PhotoRepository` 流式分页，每批 200、350ms 节流，无窗口裁剪，提交后在 VM 内合并 `PhotoTidy/DataLayer/LibraryStore.swift:29-103`。
- **会话管理**：  
  - main：每个 scope 对应 `PhotoSession`，包含 offset/窗口限制/trim 计数，VM 通过 `sessionManager` 选择/预热/切换会话 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:60-79`, `PhotoTidy/DataLayer/PhotoSession/PhotoSession.swift:12-50`。  
  - v1.0：单一 `items + sessionItems` 列表，依据当前筛选或月份重建，合并时保留删除标记 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:470-546`, `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:150-180`。
- **缓存与图像通道**：  
  - main：显式 `ThumbnailStore` / `FullImageStore`，缩略图预热走 `ImagePipelineAdapter`，描述符缓存独立于主列表 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:58-64`, `PhotoTidy/DataLayer/Thumbnails/ThumbnailStore.swift:1-92`。  
  - v1.0：直接用 `ImagePipeline` + `PhotoLoader` 预热，未分离缩略图仓库；新增 `PhotoItemBuilder` 在构建时应用分析缓存 `PhotoTidy/DataLayer/PhotoItemBuilder.swift:4-47`。
- **预热/零延迟策略**：  
  - main：存在“预热全量会话”与窗口裁剪（60/120）逻辑，避免内存膨胀 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:73-79`, `PhotoTidy/DataLayer/PhotoSession/PhotoSession.swift:31-36`。  
  - v1.0：无窗口裁剪，主线程直接承载完整合并列表；首屏仍依赖 `MetadataRepository` 缓存，但真实资源加载压力更集中 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:59-95`, `PhotoTidy/DataLayer/LibraryStore.swift:48-103`。
- **分析节奏**：  
  - main：以 `analysisChunkSize`/`baseAnalysisPause` 分批背景分析，触发受 `allowBackgroundAnalysis` 控制 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:65-70`。  
  - v1.0：批次到达即调度全量分析，节流 2s，未按 chunk 切分，容易在大批量时产生热量 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:662-729`。

## 详细对比
- **分页大小与窗口管理**  
  - main：`PhotoSessionManager.batchSize` 10/18，`windowLimit` 60/120（可剪裁旧元素）`PhotoTidy/DataLayer/PhotoSession/PhotoSessionManager.swift:31-90`, `PhotoTidy/DataLayer/PhotoSession/PhotoSession.swift:31-38`。  
  - v1.0：`LibraryStore` 固定 200/批，默认不裁剪；`PhotoLoader` 仍存在但仅用于预热 `PhotoTidy/DataLayer/LibraryStore.swift:29-103`, `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:476-546`。  
  - 影响：v1.0 每批吞吐大、内存峰值高，且没有窗口回收，长时间运行更易发热。

- **数据归并与 UI 同步**  
  - main：`PhotoSession` 更新通过 delegate 推到 VM，VM 重建 `sessionItems`，并可在 scope 切换时预热全量会话 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:60-79`, `PhotoTidy/DataLayer/PhotoSession/PhotoSession.swift:31-36`。  
  - v1.0：`handleLibraryEvent` 事件驱动，`mergeItemsPreservingFlags` 保留待删标记、再按时间排序，避免重置 UI 状态 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:498-546`, `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:598-611`, `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:150-180`。

- **图像加载与预热**  
  - main：缩略图层独立，支持按 target 预热 (`.tinderCard` 等)，并缓存 `AssetDescriptor`，减少重复查询 `PhotoTidy/DataLayer/Thumbnails/ThumbnailStore.swift:1-92`。  
  - v1.0：依旧通过 `ImagePipeline`/`PhotoLoader` 预热，但缺少分级 target 与 descriptor 缓存，压力集中在主列表加载 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:472-546`。

- **缓存与首屏体验**  
  - main：首屏依赖 `MetadataRepository` + `ThumbnailStore` 预热，会话窗口限制让首批更快填充。  
  - v1.0：首屏也用 `MetadataRepository`，但首批 200 的真实资源加载才能填满 UI，零延迟感弱；分析缓存应用集中在 `PhotoItemBuilder` 构建阶段 `PhotoTidy/DataLayer/PhotoItemBuilder.swift:4-47`。

- **背景分析节奏**  
  - main：`analysisChunkSize`=24，`baseAnalysisPause`=120ms 控制节奏 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:65-66`。  
  - v1.0：分析在列表合并后统一排程，缺少 chunk 切分，易在批量页回调后持续占用 CPU `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:662-729`。

## 结论与建议
- 如果追求 1.0 的“零延迟”体感，可回退到 main 的 Session/缩略图预热策略：小批次 + 窗口限制 + 预热多级缩略图，避免一次性大批吞吐。
- 也可在 v1.0 上微调：将 `LibraryStore` 首批/分页调小（如 60-80）、增加窗口裁剪与 descriptor 缓存、引入 chunked 分析，或复用 main 的 `ThumbnailStore`/`PhotoSessionManager` 以恢复丝滑度。  

（参考文件：main 分支 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:1-79`, `PhotoTidy/DataLayer/PhotoSession/PhotoSessionManager.swift:26-113`, `PhotoTidy/DataLayer/Thumbnails/ThumbnailStore.swift:1-92`; v1.0 分支 `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:59-95`, `PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:470-546`, `PhotoTidy/DataLayer/LibraryStore.swift:29-103`, `PhotoTidy/DataLayer/PhotoItemBuilder.swift:4-47`.) 
