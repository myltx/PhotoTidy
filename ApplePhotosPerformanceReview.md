# 苹果级性能对照审查

## 达标点
- `MetadataRepository` 先读取 `MetadataCacheStore` 快照再刷新，首帧即可展示月份统计与分类计数，符合阶段 A“元数据先行”(PhotoTidy/DataLayer/Metadata/MetadataRepository.swift:17)。
- `TimeMachineView` 借 `normalizedSections` 永远渲染 12 个月占位，初次进入不会白屏 (PhotoTidy/Views/TimeMachineView.swift:3)。
- `TimeMachineMetaStore` 将 `TimeMachineProgressStore` 与 `SkippedPhotoStore` 聚合成月度信息，无需 PhotoKit 全量扫描即可展示进度徽章 (PhotoTidy/TimeMachineZeroLatency/TimeMachineMetaStore.swift:9)。
- 零延迟时光机会话使用 `LargeImagePager` 只缓存当前/前/后一张大图，满足阶段 C 窗口缓存要求 (PhotoTidy/Services/LargeImagePager.swift:5)。
- `ZeroLatency/PhotoLoader` + `ImageCache` 已具备分页、预取与 LRU 预热，说明阶段 B/C 的基础组件可复用 (PhotoTidy/ZeroLatency/PhotoLoader.swift:20)。
- Vision 结果通过 `PhotoAnalysisCacheStore` 共享，`MetadataRepository`、时光机与清理流程均可复用同一份分析缓存，符合分层缓存思路 (PhotoTidy/Services/PhotoAnalysisCacheStore.swift:3)。

## 不达标点
- 所有 SwiftUI 缩略图仍直连 `PHCachingImageManager`，未接入统一内存/磁盘缓存；`ImagePipeline` 只在预取时使用，无法保证 10–40 ms 缩略图体验 (PhotoTidy/Views/AssetThumbnailView.swift:6)。
- 阶段 C 只在零延迟时光机启用；普通 Tinder 卡片始终加载大图/视频，违背“进入全屏才加载大图”的原则 (PhotoTidy/Views/PhotoCardView.swift:14)。
- `MetadataSnapshot` 缺少封面 ID 与时间范围，点击月份仍要解析 Moment 集合，阶段 A 不达标 (PhotoTidy/DataLayer/Metadata/MetadataSnapshot.swift:6)。
- `TimeMachineMonthDetailViewModel` 与 `PhotoCleanupViewModel.monthItems` 依旧一次性遍历整月/整库，未真正分页 (PhotoTidy/TimeMachineZeroLatency/TimeMachineMonthDetailViewModel.swift:43; PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:1240)。
- `PhotoCleanupViewModel`、零延迟模块各自维护 `PhotoRepository`/`PhotoLoader`/`ImagePipeline`，缺少统一 PhotoStore，导致重复扫描 (PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:62; PhotoTidy/ZeroLatency/ZeroLatencyPhotoViewModel.swift:15)。
- `ingestAssets` 在主线程复制整个 `analysisCache.snapshot()` 并逐条构建 `PhotoItem`，严重阻塞 UI (PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:572)。

## 性能风险点
- 任何分页或月份预取都会触发 `ingestAssets` 的主线程重构，导致“滑动/首屏卡顿” (PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:572)。
- `TimeMachineMonthDetailViewModel` 进入月份前需遍历整月 asset IDs，月内照片越多越容易“点进月份慢” (PhotoTidy/TimeMachineZeroLatency/TimeMachineMonthDetailViewModel.swift:43)。
- `prefetchMonthAssetsIfNeeded` 对多个月并行抓取 400 张原图并预热，易触发内存与 PHImageManager 请求风暴 (PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:1444)。
- `AssetRichPreviewView` 会自动加载视频/Live Photo/GIF，滑动时不断触发大图 IO，造成“滑动卡顿” (PhotoTidy/Views/AssetRichPreviewView.swift:37)。
- `TimeMachineMetaStore.fetchCreationDates` 在 skipped 记录多时仍需遍历 PhotoKit，阶段 A 难以维持 0 ms (PhotoTidy/TimeMachineZeroLatency/TimeMachineMetaStore.swift:82)。

## 必须改进的技术点
1. **统一 PhotoDataStore**：以 actor 托管 `PhotoRepository`、`PhotoLoader`、`ImagePipeline`、`LargeImagePager`，所有模块通过同一 Store 访问阶段 A/B/C 数据，杜绝重复扫描 (PhotoTidy/ViewModels/PhotoCleanupViewModel.swift:62)。
2. **扩展 MetadataSnapshot**：缓存每月封面 asset id、时间范围，`TimeMachineZeroLatencyViewModel` 只读该缓存即可 0 ms 渲染 (PhotoTidy/DataLayer/Metadata/MetadataSnapshot.swift:6)。
3. **ThumbnailPipeline 普及**：让 `AssetThumbnailView`、`AssetRichPreviewView` 使用 `ImagePipeline` 的内存+磁盘缓存，保证 150–300px 缩略图在 10–40 ms 内返回 (PhotoTidy/Views/AssetThumbnailView.swift:6)。
4. **分页化 TimeMachine/Session**：引入 `PagedAssetSequence`，`TimeMachineMonthDetailViewModel` 与 `PhotoCleanupViewModel` 通过 `PhotoRepository.fetchNextBatch`/`AssetIndexStore` 逐批加载，废弃全量 filter (PhotoTidy/TimeMachineZeroLatency/TimeMachineMonthDetailViewModel.swift:43)。
5. **异步化分析缓存**：把 `analysisCache.snapshot()` 与 `PhotoItem` 构建挪到后台队列，或让 `PhotoAnalysisCacheStore` 以 actor diff 推送，主线程只整合结果 (PhotoTidy/Services/PhotoAnalysisCacheStore.swift:31)。
6. **Skeleton & Lazy Rendering**：Dashboard、专项处理、月份详情等默认展示骨架并绑定 Stage A 数据，真正的缩略图/大图异步替换，避免白屏。

## 推荐的新架构（数据流 / 缓存策略）
- **Stage A – MetadataStore**：启动即从 `MetadataCacheStore` 播发 `MetadataSnapshot`（含封面 ID/时间范围/进度），UI 即刻渲染骨架。
- **Stage B – ThumbnailStore**：封装 `ImagePipeline`+`ImageDiskCache`+`PHCachingImageManager`，暴露 `ThumbnailHandle`，内部维持 L1(NSCache 最近 3 张)、L2(磁盘)、L3(PhotonKit) 三层缓存。
- **Stage C – FullImageStore**：统一管理 `LargeImagePager`，根据 `PhotoSession` 维持当前/前/后一张全屏图，提供 `prepare(session:)` API 给 Tinder 卡片、全屏预览、相似比对。
- **PhotoSessionManager**：所有功能模块（Tinder、时光机、相似/模糊、大文件等）通过 `PhotoSession` 抽象定义 scope 与 batch size，由 `PhotoRepository.fetchNextBatch` 驱动并通过 `IntersectionObserver/OnAppear` 触发下一批。
- **AnalysisStore**：`BackgroundJobScheduler` 的 Vision 结果写入 `PhotoAnalysisCacheStore` actor，并以增量更新 Stage A/B，使相似/模糊状态在所有模块中同步。

## 最终性能预期
- 维持现状（主线程构建、一次性月加载、无统一缓存）无法达到苹果级 0 ms／无顿卡：首屏受 `analysisCache.snapshot()` 阻塞，月份入口需等待整月解析，大图只在部分路径优化。
- 落实上述架构后：  
  - Stage A 直接播发缓存，首屏骨架渲染可压到 <5 ms；  
  - Stage B 统一缩略图缓存 + 分页，月份/分类列表在 10–40 ms 内加载下一批；  
  - Stage C 共享大图窗口，卡片翻页与全屏展示 80–120 ms 内完成。  
整体体验可逼近 Apple Photos 的“0 ms 延迟、无顿卡”级别。
