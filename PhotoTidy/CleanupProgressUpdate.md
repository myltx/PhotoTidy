# 清理进度持久化更新（2025-11-29）

## 背景
为确保用户关闭 App 后能继续上次的清理流程，本次迭代实现了 **时光机（月度整理）** 与 **首页智能清理** 两套独立的本地进度系统，全部数据仅保存在用户设备上。

## 主要改动
1. **TimeMachineMonthProgress（`Models/TimeMachineMonthProgress.swift`）**  
   - 记录年月、处理进度（processedCount）、用户勾选待删、跳过的 `localIdentifier` 以及是否标记“已清理”。  
   - 遵循 `Codable`/`Equatable`，同时提供 `key` 与 `isMeaningful` 便于存储。

2. **TimeMachineProgressStore（`Services/TimeMachineProgressStore.swift`）**  
   - 基于 `UserDefaults` 的本地仓库，通过 JSON 编码缓存所有月份进度。  
   - 提供保存/读取、更新处理进度、同步选中/跳过状态、标记月份“已清理”以及清空指定照片记录的方法。  
   - 采用 `NSLock` 保护多线程访问，所有操作均在本地完成，不触网。

3. **PhotoCleanupViewModel 集成（`ViewModels/PhotoCleanupViewModel.swift`）**  
   - 注入并持有 `TimeMachineProgressStore`，初始化时恢复历史选择状态。  
   - 在月份模式下会话切换时自动读取 `processedCount`，恢复到正确的 `currentIndex`。  
   - 用户执行标记删除、保留、跳过、撤销待删、真正删除照片以及标记月份“已清理”时，实时写回本地存储。  
   - 清理成功后同步删除已处理照片的本地记录，防止陈旧数据残留。

4. **SmartCleanupProgress（`Models/SmartCleanupProgress.swift`）**  
   - 记录首页智能清理的最后使用分类、锚点 `photoId`、待删标记以及时间戳。  
   - `SmartCleanupProgressStore` 负责 JSON 持久化，供首页恢复“继续上次整理”状态。

5. **Dashboard & ViewModel 联动**  
   - `PhotoCleanupViewModel` 现在同时注入 `TimeMachineProgressStore` 与 `SmartCleanupProgressStore`，并新增 `smartCleanupResumeInfo`/`resumeSmartCleanup()`。  
   - `DashboardView` 的英雄卡片完全依赖 `SmartCleanupProgress` 与全局待删状态，月度进度不再影响首页逻辑。  
   - 待删区任何变更都会同步更新 `SmartCleanupProgress` 的 `hasPendingItems`，确保首页提示与实际状态一致。

## 数据字段与含义
| 字段 | 说明 |
| --- | --- |
| `processedCount` | 当前月份已处理到的卡片索引，重新进入时自动定位 |
| `selectedPhotoIds` | 被用户标记进入“待删除”区的 `PHAsset.localIdentifier` |
| `skippedPhotoIds` | 用户手动跳过的 `localIdentifier` |
| `isMarkedCleaned` | 用户是否确认该月份已整理完毕 |

## 使用提示
- `TimeMachineProgressStore` 可单例化注入，若未来需单元测试，可使用自定义 `UserDefaults`。  
- 若要在 UI 中展示进度，可通过 `timeMachineProgressStore.progress(year:month:)` 获取对应 `TimeMachineMonthProgress`。  
- 数据已按月份自动分组；若想扩展到非月份维度，可在 `TimeMachineMonthProgress` 中新增键定义并扩展 `store` 逻辑。

如需在文档中引用此更新，可直接链接到上述文件路径。欢迎根据需要继续扩充 `TimeMachineMonthProgress` 的统计字段，或结合 SmartCleanupProgress 做更细致的体验优化。
