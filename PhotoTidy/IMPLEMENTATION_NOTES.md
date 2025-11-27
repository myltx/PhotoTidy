## PhotoTidy 智能相册清理实现说明

本项目在原有基础上，主要围绕两块做了增强：

1. 「全相册滑动整理」的高保真交互与卡片堆叠效果  
2. 「相似照片」的高保真 UI + 更合理的相似度算法（时间 + pHash + Vision FeaturePrint）

下面按模块记录实现思路与关键代码位置，方便后续维护或重构。

---

## 1. 全相册滑动整理（Full Swipe Cleaner）

### 1.1 入口与整体结构

- 入口：`DashboardView` 中「全相册整理」卡片与「开始」按钮：  
  - 调用 `viewModel.showCleaner(filter: .all)`  
  - `ContentView.MainAppView` 使用 `fullScreenCover` 弹出 `CleanerContainerView`

- 文件：`PhotoTidy/Views/CleanerContainerView.swift`  
  - 负责整个清理流程的页面结构：顶部返回 + 待删数、中间卡片栈、底部操作按钮。

结构：

- 背景：`LinearGradient(systemGray6 -> systemBackground)`，模拟设计稿里的浅灰 phone-frame 背景。
- Header：`CleanerHeader`（返回 + 标题 + 待删数量）
- 中间：
  - 有数据时：顶部日期条 `SwipeDateHeaderView` + 卡片堆叠 `CardStackView`
  - 没数据时：`NoMorePhotosView`
- 底部：
  - `PhotoMetaView`：展示文件名、拍摄日期、大小
  - `CleanerFooter`：左「删除」、右「保留」两个圆形按钮

### 1.2 顶部日期条 SwipeDateHeaderView

文件：`CleanerContainerView.swift`

作用：在滑动整理页顶部显示当前卡片所属时间，如「2023年 10月」「昨天/今天/10月12日」。

关键逻辑：

- 从 `viewModel.currentItem?.creationDate` 计算：
  - 年月文案：`yyyy年 M月`
  - 相对日期：`今天 / 昨天 / M月d日`
- 使用一个顶部渐变背景，营造设计稿中的「顶部浅灰渐变」效果。

### 1.3 卡片堆叠与滑动交互（CardStackView）

文件：`PhotoTidy/Views/CardStackView.swift`

职责：

- 从 `viewModel.sessionItems` 中取当前索引开始的 3 张，做成堆叠卡片。
- 顶部卡片支持手势：左滑加入待删区、右滑保留、上滑跳过。

核心点：

- `start = currentIndex`，`end = min(start + 3, sessionItems.count)`  
  `stackSlice = sessionItems[start..<end]`
- 堆叠顺序：先渲染“更靠后的”，最后渲染当前卡片，保证当前卡片在最上层。
- `PhotoCardViewWrapper` 根据 `indexInStack` 计算：
  - `scale`：越靠下越小
  - `yOffset`：越靠下越向下偏移
  - `baseRotation`：给每层一点基础角度，让堆叠更有层次感
  - `opacity`：下面的卡片略微更淡

滑动行为：

- `DragGesture` 只作用于最上层卡片：
  - 水平位移为主时：
    - `translation.width > threshold`：右滑 → `viewModel.keepCurrent()`
    - `translation.width < -threshold`：左滑 → `viewModel.markCurrentForDeletion()`
  - 垂直位移为主时：
    - `translation.height < -verticalThreshold`：上滑 → `viewModel.moveToNext()`
- 手势结束后，用 `.spring()` 动画将 `dragOffset` 复位。

滑动实时反馈：

- 顶部右侧徽标：
  - `KEEP`：右滑趋势（保留）
  - `DELETE`：左滑趋势（删除）
  - `SKIP`：上滑趋势（跳过）
  - 通过判断 `dragOffset` 的方向和大小动态显示。
- 底部中间文案：
  - 「上滑跳过」+ `chevron.up`，提示用户还有上滑这个手势。

### 1.4 单张卡片视觉（PhotoCardView）

文件：`PhotoTidy/Views/PhotoCardView.swift`

职责：渲染单个媒体的缩略图、文件大小，贴近设计稿的大卡片样式。

关键点：

- 使用 `AssetThumbnailView` 获取 PHAsset 缩略图。
- 纵横比调整为 3:4，更像纵向照片。
- 视觉效果：
  - 圆角 24
  - 阴影：`shadow(color: .black.opacity(0.1), radius: 12, y: 8)`
  - 顶部渐变遮罩提升文字可读性
  - 顶部左侧胶囊显示 `fileSizeDescription`
  - 外圈一圈浅白描边，让卡片“抠”出背景。

### 1.5 用户行为与状态流转

文件：`PhotoTidy/ViewModels/PhotoCleanupViewModel.swift`

- `currentIndex` 指向当前会被卡片栈渲染的起始位置。
- `currentItem` 计算属性：`sessionItems[safe: currentIndex]`
- 动作：
  - `moveToNext()`：`currentIndex + 1`，超出时设为 `sessionItems.count`
  - `markCurrentForDeletion()`：
    - 在 `items` 里找到当前 id，`markedForDeletion = true`
    - `moveToNext()`
  - `keepCurrent()`：不改标记，只 `moveToNext()`

`sessionItems` 的生成由 `updateSessionItems(for:)` 控制，根据当前 filter（全相册、相似、模糊、截图/文档、大文件）过滤 `items`。

---

## 2. 相似照片页面 UI（SimilarComparisonView）

文件：`PhotoTidy/Views/SimilarComparisonView.swift`

目标：实现高保真相似照片界面 + 扩展支持「堆叠」和「对比」两种布局。

### 2.1 分组来源

- 从 `viewModel.items` 中把 `similarGroupId != nil` 的照片按 groupId 收集成二维数组：

  ```swift
  var dict: [Int: [PhotoItem]] = [:]
  for item in viewModel.items {
      guard let gid = item.similarGroupId else { continue }
      dict[gid, default: []].append(item)
  }
  ```

- groups 再按时间排序，`currentGroupIndex` 控制当前显示第几组。

### 2.2 布局模式：堆叠 / 对比

使用本地枚举管理模式：

```swift
private enum SimilarLayoutMode {
    case stacked     // 堆叠卡片，高保真原稿风格
    case sideBySide  // 左右并排对比
}
```

状态：

- `@State private var layoutMode: SimilarLayoutMode = .stacked`
- Header 下方有一个小的 layoutToggle，两个按钮：
  - 「堆叠」：图标 `square.stack.3d.forward.dottedline.fill`
  - 「对比」：图标 `square.split.2x1.fill`
- 切换按钮有轻微高亮、描边和弹簧动画，提升可感知度。

内容区域根据模式切换：

```swift
if layoutMode == .stacked {
    stackedCards(for: group, hero: hero)
} else {
    sideBySideCards(for: group, hero: hero)
}
```

#### 堆叠模式

- 前景：当前「最佳」照片，带「⭐️ 最佳」徽标、品牌色描边、更亮、更大。
- 背景：从同组中找一张非 hero 的照片，偏灰、缩小、放在右下方。

#### 对比模式

- 左侧：另一张候选照片（若存在）  
- 右侧：当前「最佳」照片  
- 两张宽度约 150，便于在手机屏幕中直观对比细节。

### 2.3 卡片状态与切换反馈

共用一个 `comparisonCard(for:isHero:compact:)` 组件：

- `isHero` 决定：
  - 阴影深浅
  - 外边框颜色（品牌色 vs 浅灰）
  - 图片灰度与透明度
  - 上方徽标内容（「最佳」 vs 「未选中」）
  - scale（略放大/略缩小）
- `compact` 决定统一布局和尺寸（堆叠 vs 对比模式）。

点击卡片：

- `onTapGesture` 中用 `.spring()` 动画切换 `selectedId`，视觉上有明显的切换反馈，即使两张原图完全相同，用户仍能感知到「焦点」改变。

### 2.4 流程控制

- 顶部标题：「第 x / n 组」，根据 `currentGroupIndex` 与 `groups.count` 计算。
- `保留最佳` 按钮逻辑：
  - 找到当前 hero：
    - 对这一组中 hero 以外的所有照片调用 `viewModel.setDeletion($0, to: true)` → 标记待删
  - 然后 `moveToNextGroupOrDismiss()`：
    - 若还有下一组 → `currentGroupIndex += 1`
    - 否则 `dismiss()` 关闭页面。

---

## 3. 相似照片算法（时间 + pHash + Vision FeaturePrint）

文件：

- 模型：`PhotoTidy/Models/PhotoItem.swift`
- 算法服务：`PhotoTidy/Services/ImageAnalysisService.swift`
- 分析流程：`PhotoTidy/ViewModels/PhotoCleanupViewModel.swift`（`analyzeAllItemsInBackground()`）

目标：比原先单一阈值聚类更合理：

1. 全库遍历，每张照片预计算特征；
2. 用「时间 + pHash」做粗筛，只在局部候选里比较；
3. 在候选里用 Vision FeaturePrint 精分组；
4. 按距离区分「重复」和「轻微差异」；
5. 形成多个 `similarGroupId` 与 `similarityKind`。

### 3.1 PhotoItem 中的分析字段

新增：

- `pHash: UInt64?`：感知哈希（64bit）
- `similarGroupId: Int?`：相似组 ID
- `similarityKind: SimilarityGroupKind?`：
  - `.duplicate`：几乎完全一致
  - `.similar`：轻微差异（姿势、表情、小移动等）

### 3.2 预计算阶段

在 `analyzeAllItemsInBackground()` 中：

1. 遍历所有 `analyzedItems`（从 `items` 拷贝来的快照）。
2. 对每张图请求 256x256 缩略图：
   - 计算清晰度 `blurScore`
   - 曝光异常 `isExposureBad`
   - 是否模糊 `isBlurredOrShaky`
   - 非截图照片做文档检测 `isDocumentLike`
   - 大文件标记 `isLargeFile`
   - 非视频的：
     - 计算 Vision FeaturePrint → 存入 `featurePrints[index]`
     - 计算 pHash → 存入 `pHashes[index]` 和 `analyzedItems[index].pHash`

### 3.3 粗分组：时间窗口 + pHash

前提：至少有一部分照片成功计算了 FeaturePrint。

1. **按拍摄时间排序索引**：
   - `indices = 0..<total` 按 `creationDate` 升序排序。
2. **按时间窗口切分 bucket**：
   - 使用 `timeWindow = 3 秒`（可调），从最早时间开始，时间差在窗口内的加入同一 bucket。
   - 每个拥有 2 张以上照片的 bucket 视为一批连拍候选。
3. **在 bucket 内用 pHash 粗筛**：
   - 对每个 bucket：
     - 遍历未使用的 idxI：
       - 若 `pHash` 存在，尝试与后续 idxJ 的 `pHash` 比较 `hammingDistance`
       - 若 `distance < 10`，归为同一 candidate group
     - candidate group 中照片数 > 1 的，加入 `candidateGroups`。

这一步主要减少后续需要做 Vision 距离比较的照片对数量，将相似计算限制在「时间接近 + 结构相似」的子集合内。

### 3.4 精分组：Vision FeaturePrint 距离

对每个 `candidateGroup` 内的索引列表，执行两轮聚类：

- 共享状态：
  - 全局递增 `globalGroupId`
  - `duplicateThreshold = 10.0`
  - `similarThreshold = 25.0`
  - `assigned[idx]` 标记已归组的照片

1. 先处理「重复组」（更严格）：
   - 对每个未被 assigned 的 idxI：
     - 遍历 idxJ：
       - if `distance(fp1, fp2) < duplicateThreshold` → 加入 cluster
   - `cluster.count > 1` 的赋予一个新的 `similarGroupId`，`similarityKind = .duplicate`，并标记 `assigned = true`。

2. 再处理「轻微差异组」：
   - 再次遍历未 assigned 的 idxI：
     - 遍历 idxJ：
       - if `distance(fp1, fp2) < similarThreshold` → 加入 cluster
   - 同样将 cluster 中照片赋给新的 `similarGroupId`，`similarityKind = .similar`。

说明：

- 先做“重复”，可以保证重复照片不会再被归入“轻微差异”组。
- `similarThreshold` 可以根据实际相册分布调整（例如 25–30 更宽松）。

### 3.5 Vision 不可用时的兜底策略

如果所有 FeaturePrint 都是 nil（比方某些模拟器环境），则退化为简单重复检测：

- key = 「宽 x 高 + 文件大小」
- 对相同 key 的列表：
  - 若数量 > 1，则设为一组：`similarGroupId = groupId`，`similarityKind = .duplicate`

这样至少能识别「完全相同文件」级别的重复照片。

---

## 4. 后续可以扩展的方向（备忘）

1. **利用 similarityKind 调整 UI 文案**：
   - 在相似界面顶部显示「连拍」或「轻微差异」的小标签。
   - Dashboard 上分别统计重复照片数量 vs 相似照片数量。

2. **自动推荐“最佳”照片**：
   - 在每个相似组内部：
     - 选择 `blurScore` 高、`exposureIsBad = false`、`fileSize` 较大的作为默认 hero。
   - 当前 UI 已支持用户点击切换最佳，这里可以加上智能默认值。

3. **更多布局**：
   - 在对比模式下增加底部缩略图条（类似 Lightroom 的候选条）。
   - 对于 3 张以上的相似组，支持左右滑切换要对比的候选。

4. **性能优化**：
   - 目前分析流程在一条后台队列中顺序执行，后续可以：
     - 对非常大的相册分批分析（例如一次 500 张）；
     - 缓存 FeaturePrint/pHash 到本地，避免每次启动都全量分析。

以上即当前实现的主要功能与思路，后续调整相似度阈值或 UI 时，可直接对照本文件快速定位到对应的模块和参数。 

