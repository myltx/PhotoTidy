# 清理进度持久化更新（2025-11-29）

## 背景
为确保用户关闭 App 后能继续上次的清理流程，本次迭代实现了对每个月清理进度与用户操作（选择/跳过/完成）的本地持久化，全部数据仅保存在用户设备上。

## 主要改动
1. **CleanupProgress（`Models/CleanupProgress.swift`）**  
   - 记录年月、处理进度（processedCount）、用户勾选待删、跳过的 `localIdentifier` 以及是否标记“已清理”。  
   - 遵循 `Codable`/`Equatable`，同时提供 `key` 与 `isMeaningful` 便于存储。

2. **CleanupProgressStore（`Services/CleanupProgressStore.swift`）**  
   - 基于 `UserDefaults` 的本地仓库，通过 JSON 编码缓存所有月份进度。  
   - 提供保存/读取、更新处理进度、同步选中/跳过状态、标记月份“已清理”以及清空指定照片记录的方法。  
   - 采用 `NSLock` 保护多线程访问，所有操作均在本地完成，不触网。

3. **PhotoCleanupViewModel 集成（`ViewModels/PhotoCleanupViewModel.swift`）**  
   - 注入并持有 `CleanupProgressStore`，初始化时恢复历史选择状态。  
   - 在月份模式下会话切换时自动读取 `processedCount`，恢复到正确的 `currentIndex`。  
   - 用户执行标记删除、保留、跳过、撤销待删、真正删除照片以及标记月份“已清理”时，实时写回本地存储。  
   - 清理成功后同步删除已处理照片的本地记录，防止陈旧数据残留。

4. **交互微调（`Views/CardStackView.swift`）**  
   - 上滑操作改为调用 `skipCurrent()`，确保跳过行为也写入本地进度。

## 数据字段与含义
| 字段 | 说明 |
| --- | --- |
| `processedCount` | 当前月份已处理到的卡片索引，重新进入时自动定位 |
| `selectedPhotoIds` | 被用户标记进入“待删除”区的 `PHAsset.localIdentifier` |
| `skippedPhotoIds` | 用户手动跳过的 `localIdentifier` |
| `isMarkedCleaned` | 用户是否确认该月份已整理完毕 |

## 使用提示
- `CleanupProgressStore` 为单例（`shared`），若未来需单元测试，可注入自定义 `UserDefaults`。  
- 若要在 UI 中展示进度，可通过 `progressStore.progress(year:month:)` 获取对应 `CleanupProgress`。  
- 数据已按月份自动分组；若想扩展到非月份维度，可在 `CleanupProgress` 中新增键定义并扩展 `store` 逻辑。

如需在文档中引用此更新，可直接链接到上述文件路径。欢迎根据需要继续扩充 `CleanupProgress` 的统计字段。
