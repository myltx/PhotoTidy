# 性能基线记录（Stage 0）

> 目标：在逐步迁移到苹果级零延迟架构前，保留当前主分支的构建与首帧表现，以便后续对比。

## 1. 环境信息

- 设备 / 模拟器：iphone 14 ProMAX
- iOS 版本：18.7.1
- Xcode 版本：26.1.1 (17B100)
- Commit/Tag：

## 2. 构建结果

运行命令：

```bash
xcodebuild -project PhotoTidy.xcodeproj \
  -scheme PhotoTidy \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  clean build
```

请在下方粘贴关键输出（成功/警告/失败）：

- 结果：✅ 成功（2024-05-XX）
- 耗时：约 2m34s

## 3. 首帧与交互基线

- Dashboard 进入耗时（空白 → 骨架）：约 320 ms（iPhone 14 Pro Max 实机）
- 时光机进入耗时：约 12 s（首次进入）
- Tinder 清理滑动流畅度（掉帧说明）：偶见 1~2 帧掉帧，怀疑与主线程 `ingestAssets` 计算相关
- 截图/录屏链接：

## 4. 备注

- 当前 Feature Toggle 配置：`FeatureToggles.enableApplePhotosArchitecture = false`
- 若有其它影响因素（真机/后台任务），请记录。

> 填写完成后，将此文件纳入 PR 说明，后续每个阶段结束时更新对比数据。
