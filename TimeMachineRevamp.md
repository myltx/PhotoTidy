## 时光机（Time Machine）重构说明

### 目标概述
- 去除旧版依赖 `processedCount / lastIndex` 的“待处理数量”推算，改为直接展示真实的整理来源。
- 以月份为颗粒度，用「待删」「跳过」「已确认」三类数据来推导状态与进度。
- 通过 SwiftUI 重绘页面结构，突出三种状态：未开始（浅灰）、进行中（黄色进度）、已完成（绿色标签）。

### 数据模型
| 类型 | 说明 |
| --- | --- |
| `MonthInfo` | 月份汇总，存储年月、四个数量字段以及 `status` / `progress`。`processedCount` 由三个来源相加得到。 |
| `CleaningStatus` | 枚举：`.notStarted / .inProgress / .completed`，附带本地化 `title`。|
| `analyzeMonthCleaningStatus` | 自由函数，按照 `processed == 0`、`processed == total`、以及其余情况返回状态，并返回 0~1 的进度百分比。|
| `TimeMachineMonthProgress` | 仅保留 `selectedPhotoIds`（待删）与 `confirmedPhotoIds`（明确保留），不再存储 processedCount/lastIndex。|

### 数据来源
1. **totalPhotos**：`PhotoCleanupViewModel.items`（PhotoKit 全量照片）按照年月分组。
2. **skippedCount**：`SkippedPhotoStore` 中 `source == .timeMachine` 的记录，缺失日期时按 `PHAsset.fetchAssets` 查询创建日期。
3. **pendingDeleteCount**：同一月份内 `PhotoItem.markedForDeletion == true` 的数量。
4. **confirmedCount**：`TimeMachineProgressStore.confirmedPhotoIds` 聚合。

> `processedCount = skipped + pendingDelete + confirmed`；进度条为 `processed / total`（缺或 0 时代入 0）。

### 视图模型
`TimeMachineTimelineViewModel`
- 订阅 `PhotoCleanupViewModel` 的 `items` / `skippedPhotoRecords` / `timeMachineSnapshots`。
- 在后台队列聚合月份数据，生成 `[YearSection]`（年 → 多个 `MonthInfo`）。
- 自动处理跳过记录缺失日期的情况，必要时向 PhotoKit 查询。
- 通过 `@Published` 输出给 SwiftUI 视图，任何来源数据变化都会实时刷新。
- **增量更新模式（最新实现）**：
  - 分别缓存 `items`、`skipped`、`confirmed` 三路贡献，记录在 `itemMetrics / skippedMetrics / confirmedMetrics`。
  - 每路数据变更只计算受影响的月份键，更新对应 `MonthInfo` 后再发布新的 `YearSection`，避免整页重建。
  - `photoDates` 缓存相册中已知的创建时间，并在需要时懒加载缺失日期，实现“首帧秒出 + 静默累加”体验。
  - 对于已经出现过的月份，只要仍然有任何指标数据，就保留其卡片并仅更新数值，同时在 SwiftUI 侧关闭 `LazyVGrid` 的隐式动画，避免卡片一闪一闪的视觉跳动。
  - 首次进入时优先探测年份范围（先用已加载的 `PhotoItem` 推断，必要时通过轻量的 `PHAsset` 查询逐年确认是否存在照片），并把结果缓存到 `UserDefaults`。每次新增年份都是在原有集合基础上做“并集”更新，因此不会因为尚未加载完所有 `PhotoItem` 而把旧年份丢失。这样即便还未拉取最新数据，也能立即渲染出用户有内容的年份，每年固定 12 个占位卡片，后续数据只是在卡片内渐进填充。

### SwiftUI 视图
`TimeMachineView`
- 头部为 `时光机` 标题 + 可选“重置”按钮（受 `FeatureToggles` 控制）。
- 主体按照年份分组，使用 `LazyVGrid` 网格展示 `MonthCard`。
- `MonthCard` 包含：
  - 月份名称、总照片数。
  - Status Badge：未开始（灰）、进行中（黄）、已完成（绿）。
  - 线性进度条（同色系），旁边文字 `进度 xx% · 已整理 processed/total`。
  - 三个 `MetricChip` 分别显示「待删 / 跳过 / 已确认」数量。
- 空状态 `EmptyTimelineView` 提示用户执行一次整理以生成数据。

### 交互逻辑调整
1. **保留（Keep）**：`keepCurrent()` 不再写入“跳过”集，而是调用 `recordConfirmation` 将照片放入 `confirmedPhotoIds`，保证不会再次进入该月卡片。
2. **跳过（Skip）**：仅写入 `SkippedPhotoStore`，`TimeMachineTimelineViewModel` 据此统计 `skippedCount` 并视为“已处理但待确认”。
3. **待删状态**：`persistSelectionState` 同步更新 `selectedPhotoIds`，并刷新快照供 UI 使用。
4. **重置**：`resetTimeMachineProgress()` 仅清空上述两类集合，不再关心 processedCount。

### 代码入口
- `Models/MonthCleaningModels.swift`: `MonthInfo` + `CleaningStatus` + 状态计算函数。
- `Services/TimeMachineProgressStore.swift`: 存储待删/已确认，并提供 `confirmPhoto`。
- `ViewModels/TimeMachineTimelineViewModel.swift`: 月份统计数据提供者。
- `Views/TimeMachineView.swift`: 新 UI。
- `ViewModels/PhotoCleanupViewModel.swift`: 发布 `timeMachineSnapshots`、维护 Skip/Confirm 之间的状态同步。

### 测试建议
1. **权限就绪**：授权照片后等待 `PhotoCleanupViewModel` 加载完毕，确保所有月份正常展示。
2. **操作链路**：
   - 在时光机月份中“删除”“跳过”“保留”，观察卡片进度变化。
   - 进入“跳过中心”处理记录后，确认 `skippedCount`、状态颜色即时更新。
3. **重置回归**：点击重置按钮，检查所有月份恢复到“未开始”灰色状态。
4. **数据持久性**：杀掉 App 重新打开，验证待删/已确认仍能恢复。
