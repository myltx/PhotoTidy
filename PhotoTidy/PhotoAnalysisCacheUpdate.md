# 相册分析缓存系统更新（2025-11-29）

## 更新背景
相册分析（模糊检测、截图/文档识别、相似分组等）在 App 重启后会重复运行，耗时且浪费设备资源。为了缩短启动时间并避免重复计算，本次迭代实现了完全本地的分析结果缓存与相册增量更新机制。

## 核心设计
- **缓存模型 `PhotoAnalysisCacheEntry`（`Models/PhotoAnalysisCacheEntry.swift`）**  
  包含 `localIdentifier`、文件大小、截图/文档/文字属性、模糊评分、pHash、序列化的 `VNFeaturePrintObservation`、相似分组 ID/类型及版本号，确保未来格式升级时可自动失效旧数据。

- **缓存仓库 `PhotoAnalysisCacheStore`（`Services/PhotoAnalysisCacheStore.swift`）**  
  采用 JSON 文件 `PhotoAnalysisCache.json`（位于沙盒 Documents），所有读写都在私有串行队列完成，支持：
  1. `snapshot()` 读取内存镜像
  2. `update(entries:)` 批量写入
  3. `pruneMissingEntries(keeping:)` 在相册删除资源后自动收敛
  4. `removeEntries(for:)` 在执行删除操作后清洁缓存
  所有数据仅存储分析结果，不包含原始图片。

- **ViewModel 集成（`ViewModels/PhotoCleanupViewModel.swift`）**  
  1. 继承 `NSObject` 并实现 `PHPhotoLibraryChangeObserver`，动态监听相册变化。  
  2. `loadAssets()` 完成后先应用缓存结果，再决定是否需要重新分析。  
  3. `analyzeAllItemsInBackground()` 读取缓存镜像，只有新的/变动的资源才会触发 Vision 计算，其余直接复用缓存。分析完成后将当前全量结果写回 JSON，保证下次启动即用。  
  4. 在用户删除照片后，缓存同步删除对应条目，避免引用失效数据。

- **其他改动**  
  - `SimilarityGroupKind` 改为 `String` Raw Value，以便编码存储。  
  - `PhotoCleanupViewModel` 的生命周期中注册/注销 PHPhotoLibrary 观察者，确保变更及时触发增量分析。

## 使用与验证建议
1. 首次启动 App 让分析完成。随后在应用沙盒的 Documents 中可看到 `PhotoAnalysisCache.json`（可通过 Xcode Device File Explorer 查看）。  
2. 关闭并重启 App，Dashboard/TimeMachine 等页面应即刻展示分析结果，`analysisProgress` 在加载时迅速到 100%。  
3. 往系统相册新增/删除若干照片，可以观察到仅新增资源会触发额外的分析请求，日志及 UI 表现明显变快。  
4. 若未来需要扩展更多指标（例如 AI 标签），可在 `PhotoAnalysisCacheEntry` 中新增字段并递增 `currentVersion`，旧缓存会自动失效。

以上改动均在本地完成，无任何数据上传，符合隐私要求。
