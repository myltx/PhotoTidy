# PhotoTidy 1.0 UI 回归计划

> 目标：复刻 1.0 版本的 UI/交互，同时沿用 `PhotoStore` 数据架构与三阶段加载管线，避免退回旧数据层。

## 全局策略
1. **数据单一来源**：所有页面只通过 `PhotoStoreFacade`/`PhotoFeedViewModel` 读取数据，禁止重新引入 `PhotoCleanupViewModel` 时代的 `PhotoItem`、`PhotoSessionManager` 等组件，如需桥接，封装新的轻量 ViewModel。
2. **渐进式迁移**：按照核心流程优先的原则逐个页面回归，确保任何阶段都能编译运行，且已有页面不依赖尚未实现的模块。
3. **一致的交互体验**：屏幕布局、动画、操作逻辑对齐 1.0（Tab 栏、滑动手势、底部按钮、清理成功弹层等），但内部数据调用全部使用新接口。

## 页面优先级与子任务

| 优先级 | 页面 / 模块 | 目标 | 关键任务 |
| --- | --- | --- | --- |
| P0 | **Dashboard（仪表盘）** | 恢复 1.0 首页样式与入口 | - 重建 `ContentView` + Tab 容器 <br> - 复刻 DashboardUI（存储进度、四大入口、待删/待确认计数） <br> - 使用 `PhotoStoreFacade.dashboard` / `decision` intent 填充数据 |
| P0 | **Carousel Review（滑动卡片）** | 主清理流程可用 | - 重用现有 `PhotoFeedViewModel(.sequential)` <br> - 回归 1.0 卡片 UI（底部按钮、顶部信息条） <br> - 滑动操作写回 `applyDecision` |
| P0 | **Settings（设置页）** | 对齐 1.0 设置/数据管理入口，替代 v2 决策中心 | - 使用 Settings Shell（Pro 卡片 + 数据管理 + 功能区） <br> - 待删/待确认入口改为 Sheet + 列表（`PhotoQueryIntent.pending`） <br> - 偏好/高级操作/权限子页可用，挂接清空/重置操作 <br> - Tab 栏与 Dashboard/Carousel 共用 ViewModel |
| P1 | **Ranked Review（专项处理）** | 四大专项入口可用 | - 基于 `.ranked(.blurred/.document)` intent 生成分页 <br> - 复刻 1.0 Grid/卡片交互 <br> - 处理多选加入待删 |
| P1 | **Grouped Review（相似组）** | Similar 页面 | - 依赖 `.grouped(.similar)` intent <br> - 恢复 1.0 横向组卡 UI 与推荐保留逻辑 <br> - 批量决策同步到 Facade |
| P2 | **Timeline（时光机）** | 年月筛选与弹窗清理 | - 使用 `.bucketed` intent 构建年份 → 月份视图 <br> - 复现月度弹窗与多选逻辑 <br> - 引入 `PhotoStoreFacade` 的月份过滤能力 |
| P2 | **附加页面** | 设置、成功总结、Trash 等 | - 根据需要逐项恢复 <br> - 依赖的统计信息改用 Dashboard / intent 数据 |

## 开发步骤（建议）
1. **Phase 1**：完成 Tab 容器 + Dashboard + Carousel + Settings（含待删/待确认入口），形成“浏览 → 决策 → 状态查看”闭环。
2. **Phase 2**：补齐 Ranked 与 Grouped，开放所有专项入口。
3. **Phase 3**：回归 Timeline、Settings、成功页等增强模块。

每个阶段结束需：
- 真机验证主要流程（授权、加载、滑动、决策写回）；
- 记录已知缺陷与待补动效；
- 更新本文件的进度标记并排期下一阶段。

## 进度记录
- [x] Dashboard（仪表盘）
- [x] Carousel Review（滑动卡片）
- [ ] Settings（设置页 / 数据管理）
- [ ] Ranked Review（专项处理）
- [ ] Grouped Review（相似组）
- [ ] Timeline（时光机 / 其它附属页）
