# 数据处理方案对比（目前实现 vs 2.0 零延迟）

> **目的**：梳理当前 `PhotoCleanupViewModel` 主导的数据处理链路与 2.0（零延迟）实现的差异，便于在 PR/文档中同步性能指标与后续优化方向。本文引用的源码/文档均在仓库根目录下可查。

## 参考资料
- `PhotoLibraryLoadingDesign.md` —— 记录 1.x（非零延迟）在启动、分页、后台预取上的策略。
- `PhotoTidy/Services/PhotoAnalysisCacheStore.swift` & `PhotoTidy/PhotoAnalysisCacheUpdate.md` —— 1.x 的 Vision 缓存/增量分析逻辑。
- `ZeroLatencyLoadingArchitecture.md` —— 2.0 方案的目标与运行指标（50 ms 主线程预算、100/200 条分页等）。
- `ZeroLatencyPipelineImplementation.md` —— 2.0 落地细节（Metadata/Photo Repository、TaskPool、BackgroundJobScheduler）。
- `PhotoTidy/DataLayer/*.swift`、`PhotoTidy/ZeroLatency/*.swift` —— 2.0 代码级实现。

## 关键指标与行为对比

| 维度 | 1.x（当前生产模式） | 2.0（零延迟模式） | 说明 / 依赖文档 |
| --- | --- | --- | --- |
| **冷启动主线程耗时** | 文档未写明；`PhotoCleanupViewModel.loadAssets()` 需一次性取 `PHFetchResult` 并同步构建 `defaultPageSize=160` 的 `PhotoItem`，首轮分析也同步触发（`PhotoLibraryLoadingDesign.md`「启动阶段」）。 | 目标控制在 50 ms，首帧完全取自缓存 `DashboardSnapshot`（`ZeroLatencyLoadingArchitecture.md:7-15`）；真实照片在授权后懒加载。 | 2.0 需要在缓存缺失时依旧保持 50 ms 预算，当前实现依赖 `MetadataCacheStore` 和 `ZeroLatencyCacheStore`。 |
| **首批真实照片数量 / 分页策略** | 首批 160 条，用户滚动触发 `loadNextPage`，后台预取延迟 1 s 启动且每个批次间隔 350 ms（`PhotoLibraryLoadingDesign.md:12-27`）。 | 启动后只拉取最近 100 条，后续按 200 条批处理；滚动窗口与后台预取由 `PhotoLoader + ImageCache` 即时驱动，无 350 ms 等待（`ZeroLatencyLoadingArchitecture.md:19-33`、`ZeroLatency/PhotoLoader.swift`）。 | 2.0 的批大小更大，但利用缓存/懒加载减轻瞬时压力。 |
| **分析任务批大小与耗时** | `analyzeAllItemsInBackground()` 会对当前已加载资产逐个运行，直到后台预取结束后再触发全量分析，未显式分批；当用户快速滚动时可能导致长时间占用（`PhotoLibraryLoadingDesign.md:31-46` + `PhotoAnalysisCacheUpdate.md`）。 | `AnalysisManager` 与 `BackgroundJobScheduler` 统一以 50 张为一批（含 Vision/模糊/文件大小），每批结束即落盘并广播（`ZeroLatencyLoadingArchitecture.md:19-30`、`ZeroLatency/AnalysisManager.swift`、`ZeroLatencyPipelineImplementation.md §3/§6`）。 | 2.0 有明确批大小与 backoff，还可通过 `TaskPool` 取消。 |
| **缓存/数据入口** | 只有 `PhotoAnalysisCacheStore`（JSON）与 `SmartCleanupProgressStore`；首屏必须等待 `PhotoCleanupViewModel` 载入 `PhotoItem` 才能展示 Dashboard（`PhotoAnalysisCacheUpdate.md`）。 | 双缓存：`MetadataCacheStore`（只含计数/月份/设备存储） + `PhotoAnalysisCacheStore`（分析条目），首屏直接渲染缓存镜像；真实资源由 `PhotoRepository` 按需注入（`ZeroLatencyPipelineImplementation.md §1-4`）。 | 2.0 的 snapshot 还包含 `monthMomentIdentifiers`、`DeviceStorageUsage`，TimeMachine 也秒开。 |
| **滚动/预取窗口** | `PhotoCleanupViewModel.updateCachingWindow` 维护宽度 90 的窗口，并在 `prefetchRange < 60` 时触发 `loadNextPage`；取消依赖 `PHCachingImageManager` 的 `stopCachingIfNeeded`（`PhotoLibraryLoadingDesign.md`「PHCachingImageManager 预加载」）。 | `ImagePipeline`（DataLayer）集中管理窗口、NSCache/LRU、磁盘缓存；`TaskPool` 可在页面离开时 cancel 全部请求（`ZeroLatencyPipelineImplementation.md §5/§9`，`PhotoTidy/DataLayer/ImagePipeline/*`）。 | 2.0 缓存体系支持更大的预览缓存且可统一清理。 |
| **时光机 / 月份数据** | 需等待 `PhotoCleanupViewModel.items` 全量载入后分组计算 `MonthInfo`，视图出现“延迟弹出”现象（`TimeMachineRevamp.md`）。 | `MetadataRepository` 启动即提供 `monthTotals` 与 `monthMomentIdentifiers`，`TimeMachineZeroLatencyViewModel` 直接基于缓存渲染 4 年占位并懒加载真实资产（`ZeroLatencyPipelineImplementation.md §3/§7/§10`）。 | 2.0 将月份解析下沉到 data layer，减少 UI 阻塞。 |
| **数据处理可取消性** | 仅依赖 `analysisGeneration` 避免旧任务覆盖，缺乏 Task 级取消/隔离（`PhotoLibraryLoadingDesign.md:37-43`）。 | `TaskPool`、`BackgroundJobScheduler`、`PhotoRepository` 全部在 actor 中维护任务句柄，页面离场立即取消（`ZeroLatencyPipelineImplementation.md §2/§5/§6`；代码：`PhotoTidy/DataLayer/TaskPool.swift`）。 | 2.0 明确支持场景切换/资源释放。 |

> **术语说明**：“1.x” 指过往的传统加载/分析流程（现已移除，仅保留文档对比）；“2.0” 指当前默认的零延迟架构。如需体验全新演示入口，仅需通过 `FeatureToggles.useZeroLatencyArchitectureDemo` 切换 RootView。

## 加载与数据处理时序

### 1.x：`PhotoCleanupViewModel` 主导
1. `PhotoLibraryService.fetchAssets` → `PHFetchResult` （一次性）。  
2. `PhotoCleanupViewModel.loadAssets()` 立即构建 160 条 `PhotoItem` 并恢复缓存状态。  
3. `analyzeAllItemsInBackground()` 针对已加载资产执行 Vision；当后台预取走完所有页后，整个库再次分析 + `PhotoAnalysisCacheStore` 写回。  
4. `TimeMachineTimelineViewModel` 依赖 `items`/`skipped`/`confirmed` 三路数据重新聚合，缺乏缓存。  
→ 优点：实现简单；缺点：冷启动必须等待 PhotoKit Query + PhotoItem 构建 + 首轮分析，Timeline 也需等真实数据。

### 2.0：`MetadataRepository + PhotoRepository` 双管线
1. 冷启动 → `MetadataCacheStore` / `ZeroLatencyCacheStore` 解码 JSON（<50 ms）→ UI 渲染 Dashboard/Timeline 骨架。  
2. 授权通过后 `PhotoLoader` 只取 100 条 `PHAsset`，`ImageCache` 预取 `0..<150` 缩略图，`AnalysisManager` 立即比对缓存并分批分析缺失条目。  
3. 用户滚动或点击功能页时才调用 `PhotoRepository.fetchNextBatch`（200 条）和 `ImagePipeline`，结果通过 `TaskPool` 管理。  
4. TimeMachine/专题列表直接读取 `metadataSnapshot` 得出数量，进入具体月份/分类时再解析真实 asset id 并注入旧版 Cleaner。  
→ 优点：首屏秒开、重任务完全后台化、任何页面都可取消任务；风险：需要确保缓存 schema 升级与 PhotoKit 变更同步。

## 优化点与待补充文档
1. **加载/分析实际耗时尚未量化**：目前只有 2.0 目标值（50 ms 主线程、50 张批处理），需在 1.x 与 2.0 上分别记录 `AppLaunch → Dashboard Render`、`分析完成` 的真实耗时，可通过 `os_signpost` 或 `MetricsKit` 记录并补入本文档。  
2. **文档串联**：建议在 `README.md` 的“架构说明”中补充“零延迟数据管线”小节，并链接至本对比文档与 `ZeroLatencyPipelineImplementation.md`。  
3. **Feature Toggle 行为**：`FeatureToggles.swift` 现只包含 UI/演示层面的开关（重置入口 + 零延迟演示 RootView），无需再考虑 1.x/2.0 数据层切换。  
4. **TimeMachine 文档补记加载链路**：`TimeMachineRevamp.md` 目前只覆盖 UI/模型，可追加“零延迟数据来源”一节，指出其依赖 `MetadataRepository.monthMomentIdentifiers`。  
5. **缓存版本与迁移**：`PhotoAnalysisCacheUpdate.md` 尚未记录 2.0 引入的 `MetadataCacheStore` / `ZeroLatencyCacheStore`，建议扩展“缓存结构”章节以覆盖两种 JSON schema，并附带回退步骤。

> 若需把本文纳入 PR，请在描述中附上 `xcodebuild` 结果及对应 Feature Toggle 组合，确保 Reviewer 可按需切换 1.x/2.0 验证体验差异。
