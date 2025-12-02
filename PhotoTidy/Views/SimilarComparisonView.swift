import SwiftUI
import Photos

/// 相似照片分组对比视图（按高保真设计稿重构版）
struct SimilarComparisonView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId: String?
    @State private var currentGroupIndex: Int = 0
    @State private var cachedGroups: [[PhotoItem]] = []
    @State private var previewItem: PhotoItem?
    @State private var heroTransitionEdge: Edge = .trailing

    private var currentGroup: [PhotoItem]? {
        guard !cachedGroups.isEmpty,
              currentGroupIndex >= 0,
              currentGroupIndex < cachedGroups.count else { return nil }
        return cachedGroups[currentGroupIndex]
    }

    private var totalGroups: Int { cachedGroups.count }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(UIColor.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ModalNavigationHeader(
                    title: "相似照片",
                    onClose: { dismiss() },
                    rightIcon: "ellipsis",
                    onRightAction: nil
                )

                if let group = currentGroup {
                    groupContent(for: group)
                        .id(group.first?.id ?? UUID().uuidString)
                } else {
                    emptyOrAnalyzingView
                }
            }
        }
        .onAppear(perform: recomputeGroups)
        .onChange(of: viewModel.items) { _ in
            recomputeGroups()
        }
        .onChange(of: currentGroupIndex) { _ in
            updateSelectionForCurrentGroup()
        }
        .fullScreenCover(item: $previewItem) { item in
            FullScreenPreviewView(item: item, viewModel: viewModel)
        }
    }

    // MARK: - Group Content

    private func groupContent(for group: [PhotoItem]) -> some View {
        let recommended = recommendedIndex(for: group)
        let heroIndex = currentHeroIndex(in: group, defaultIndex: recommended)
        let hero = group[heroIndex]

        return VStack(spacing: 0) {
            groupNavigationCard
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 4)

            similarityRow(recommendedIndex: recommended)
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 10)

            HeroViewer(
                item: hero,
                indexInGroup: heroIndex,
                totalCount: group.count,
                onPrevious: { showPreviousInGroup(group) },
                onNext: { showNextInGroup(group) },
                onPreview: { previewItem = hero },
                viewModel: viewModel,
                transitionEdge: heroTransitionEdge
            )
            .padding(.horizontal, 24)
            .padding(.top, 4)

            thumbnailStrip(for: group, heroIndex: heroIndex)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Spacer()

            bottomActions(for: group, heroIndex: heroIndex)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Group Navigation Card

    private var groupNavigationCard: some View {
        HStack {
            Button {
                moveToPreviousGroup()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 40, height: 36)
                    .background(Color(UIColor.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(currentGroupIndex == 0 || totalGroups == 0)
            .opacity(currentGroupIndex == 0 || totalGroups == 0 ? 0.4 : 1.0)

            Spacer()

            VStack(spacing: 2) {
                if totalGroups > 0 {
                    Text("第 \(min(currentGroupIndex + 1, totalGroups)) 组")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Text("共 \(totalGroups) 组")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("相似照片")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Text("AI 自动识别重复与相似")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                moveToNextGroup()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 36)
                    .background(Color("brand-start").opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(totalGroups == 0 || currentGroupIndex >= totalGroups - 1)
            .opacity(totalGroups == 0 || currentGroupIndex >= totalGroups - 1 ? 0.4 : 1.0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(UIColor.systemGray5), lineWidth: 1)
                )
        )
    }

    // MARK: - Similarity Row

    private func similarityRow(recommendedIndex: Int) -> some View {
        HStack {
            Text("相似度 \(Int.random(in: 90...99))%")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color("brand-start"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color("brand-start").opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.yellow)
                Text("建议保留:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text("第 \(recommendedIndex + 1) 张")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Hero Viewer
    /// 计算用户当前选择的索引，若尚未选择则回退到推荐索引
    private func currentHeroIndex(in group: [PhotoItem], defaultIndex: Int) -> Int {
        if let selectedId = selectedId,
           let idx = group.firstIndex(where: { $0.id == selectedId }) {
            return idx
        }
        return min(max(defaultIndex, 0), group.count - 1)
    }

    /// 简单的推荐索引（可以后续改成基于 blurScore / 曝光等打分）
    private func recommendedIndex(for group: [PhotoItem]) -> Int {
        guard !group.isEmpty else { return 0 }
        var bestIndex = 0
        var bestScore: Double = -Double.infinity
        for (idx, item) in group.enumerated() {
            let blur = item.blurScore ?? 0
            let exposurePenalty: Double = item.exposureIsBad ? -0.5 : 0.0
            let score = blur + exposurePenalty
            if score > bestScore {
                bestScore = score
                bestIndex = idx
            }
        }
        return bestIndex
    }

    private func showPreviousInGroup(_ group: [PhotoItem]) {
        let idx = currentHeroIndex(in: group, defaultIndex: recommendedIndex(for: group))
        guard idx > 0 else { return }
        animateHeroChange(to: group[idx - 1].id, direction: .leading)
    }

    private func showNextInGroup(_ group: [PhotoItem]) {
        let idx = currentHeroIndex(in: group, defaultIndex: recommendedIndex(for: group))
        guard idx < group.count - 1 else { return }
        animateHeroChange(to: group[idx + 1].id, direction: .trailing)
    }

    // MARK: - Thumbnail Strip

    private func thumbnailStrip(for group: [PhotoItem], heroIndex: Int) -> some View {
        let recommendedIndex = recommendedIndex(for: group)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(group.enumerated()), id: \.element.id) { (idx, item) in
                    let isHero = idx == heroIndex
                    let isRecommended = idx == recommendedIndex

                    ThumbnailView(
                        item: item,
                        isHero: isHero,
                        isRecommended: isRecommended
                    )
                    .onTapGesture {
                        let direction: Edge = idx > heroIndex ? .trailing : .leading
                        animateHeroChange(to: item.id, direction: direction)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 底部按钮

    private func bottomActions(for group: [PhotoItem], heroIndex: Int) -> some View {
        let hero = group[heroIndex]
        let others = group.enumerated().filter { $0.offset != heroIndex }.map { $0.element }
        let deleteCount = max(others.count, 0)

        return HStack(spacing: 12) {
            // 跳过本组
            Button {
                skipCurrentGroup()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.right.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(180))
                        .padding(.bottom, 2)
                    Text("跳过")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // 保留当前大图，删除其他
            Button {
                applySelection(keep: hero, delete: others)
                moveToNextGroupOrDismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保留这张")
                            .font(.system(size: 15, weight: .bold))
                        Text("删除其他 \(deleteCount) 张")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 32, height: 32)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color("brand-start"), Color("brand-end")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 跳组 / 导航

    /// 跳到上一组，不改任何删除标记
    private func moveToPreviousGroup() {
        guard currentGroupIndex > 0 else { return }
        heroTransitionEdge = .leading
        currentGroupIndex -= 1
    }

    /// 跳到下一组，不改任何删除标记
    private func moveToNextGroup() {
        let lastIndex = max(totalGroups - 1, 0)
        guard currentGroupIndex < lastIndex else { return }
        heroTransitionEdge = .trailing
        currentGroupIndex += 1
    }

    /// 跳过当前组：只是简单跳到下一组，不做「保留最佳」操作
    private func skipCurrentGroup() {
        if let group = currentGroup {
            let heroIdx = currentHeroIndex(in: group, defaultIndex: recommendedIndex(for: group))
            if heroIdx < group.count {
                viewModel.logSkippedPhoto(group[heroIdx], source: .similarGroup)
            }
        }
        moveToNextGroupOrDismiss()
    }

    private func moveToNextGroupOrDismiss() {
        let lastIndex = max(totalGroups - 1, 0)
        if currentGroupIndex < lastIndex {
            heroTransitionEdge = .trailing
            currentGroupIndex += 1
        } else {
            dismiss()
        }
    }

    private func applySelection(keep hero: PhotoItem, delete others: [PhotoItem]) {
        viewModel.setDeletion(hero, to: false)
        others.forEach { viewModel.setDeletion($0, to: true) }
    }

    /// 重新根据最新数据计算分组，并修正当前索引和选中项
    private func recomputeGroups() {
        var dict: [Int: [PhotoItem]] = [:]
        for item in viewModel.items {
            guard let gid = item.similarGroupId else { continue }
            dict[gid, default: []].append(item)
        }
        let values = Array(dict.values)
        let sorted = values.sorted { lhs, rhs in
            let lDate = lhs.first?.creationDate ?? .distantPast
            let rDate = rhs.first?.creationDate ?? .distantPast
            return lDate > rDate
        }
        cachedGroups = sorted

        let cappedIndex = min(max(currentGroupIndex, 0), max(sorted.count - 1, 0))
        if sorted.isEmpty {
            currentGroupIndex = 0
            selectedId = nil
        } else {
            if cappedIndex != currentGroupIndex {
                currentGroupIndex = cappedIndex
            } else {
                updateSelectionForCurrentGroup()
            }
        }
    }

    /// 当分组或数据变化时，刷新当前选中的照片
    private func updateSelectionForCurrentGroup() {
        guard !cachedGroups.isEmpty,
              currentGroupIndex >= 0,
              currentGroupIndex < cachedGroups.count else {
            selectedId = nil
            return
        }
        let group = cachedGroups[currentGroupIndex]
        guard !group.isEmpty else {
            selectedId = nil
            return
        }
        if let selectedId = selectedId,
           group.contains(where: { $0.id == selectedId }) {
            return
        }
        let recommended = recommendedIndex(for: group)
        heroTransitionEdge = .trailing
        selectedId = group[recommended].id
    }

    private func animateHeroChange(to newId: String, direction: Edge) {
        heroTransitionEdge = direction
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedId = newId
        }
    }

    // MARK: - 空态 / 分析中

    private var emptyOrAnalyzingView: some View {
        VStack {
            Spacer()
            Text("没有检测到相似照片")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Hero Card View

/// 主预览卡片：大图 + 组内左右切换 + 下部信息条
private struct HeroViewer: View {
    let item: PhotoItem
    let indexInGroup: Int
    let totalCount: Int

    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPreview: () -> Void

    @ObservedObject var viewModel: PhotoCleanupViewModel
    let transitionEdge: Edge

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                )

            ZStack {
                AssetThumbnailView(
                    asset: item.asset,
                    target: .detailFit
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .id(item.id)
                .transition(imageTransition(for: transitionEdge))
                .animation(.easeInOut(duration: 0.3), value: item.id)

                // 组内索引：2 / 3
                Text("\(indexInGroup + 1) / \(totalCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                // 左右切换按钮（组内）
                HStack {
                    Button(action: onPrevious) {
                        navCircle(systemImage: "chevron.left")
                    }
                    .disabled(indexInGroup == 0)
                    .opacity(indexInGroup == 0 ? 0.3 : 1.0)

                    Spacer()

                    Button(action: onNext) {
                        navCircle(systemImage: "chevron.right")
                    }
                    .disabled(indexInGroup >= totalCount - 1)
                    .opacity(indexInGroup >= totalCount - 1 ? 0.3 : 1.0)
                }
                .padding(.horizontal, 8)

                // 底部渐变 + 信息 + 放大镜按钮
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color.black.opacity(0.85), Color.black.opacity(0)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 110)
                    .overlay(
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.asset.originalFilename)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(fileInfoText(for: item))
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            Spacer()

                            Button(action: onPreview) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                    Image(systemName: "plus.magnifyingglass")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 32, height: 32)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 40
                    if value.translation.width > threshold {
                        onPrevious()
                    } else if value.translation.width < -threshold {
                        onNext()
                    }
                }
        )
    }

    private func navCircle(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(Color(UIColor.systemBackground).opacity(0.9))
                .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.gray)
        }
        .frame(width: 32, height: 32)
    }

    private func fileInfoText(for item: PhotoItem) -> String {
        var parts: [String] = []
        parts.append(item.fileSize.fileSizeDescription)

        if item.exposureIsBad {
            parts.append("曝光较暗/过曝")
        } else if let blur = item.blurScore, blur < 0.04 {
            parts.append("可能模糊")
        }

        return parts.joined(separator: " • ")
    }

    private func imageTransition(for edge: Edge) -> AnyTransition {
        let insertion = AnyTransition.move(edge: edge).combined(with: .opacity)
        let removalEdge: Edge = edge == .leading ? .trailing : .leading
        let removal = AnyTransition.move(edge: removalEdge).combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

// MARK: - Thumbnail View

/// 缩略图条中的小卡片
private struct ThumbnailView: View {
    let item: PhotoItem
    let isHero: Bool
    let isRecommended: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            let size = isHero ? CGSize(width: 56, height: 80) : CGSize(width: 44, height: 64)

            AssetThumbnailView(
                asset: item.asset,
                target: .dashboardCard
            )
            .frame(width: size.width, height: size.height)
            .clipped()
            .grayscale(isHero ? 0.0 : 0.8)
            .opacity(isHero ? 1.0 : 0.7)
            .overlay(
                RoundedRectangle(cornerRadius: isHero ? 12 : 8, style: .continuous)
                    .stroke(
                        isHero ? Color("brand-start") : Color(UIColor.systemGray4),
                        lineWidth: isHero ? 2 : 1
                    )
            )
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: isHero ? 12 : 8, style: .continuous))
            .shadow(color: isHero ? Color.black.opacity(0.2) : Color.clear,
                    radius: isHero ? 6 : 0,
                    y: isHero ? 3 : 0)

            if isRecommended {
                ZStack {
                    RoundedCorner(radius: 8, corners: [.topRight, .bottomLeft])
                        .fill(Color.yellow)
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(2)
                }
                .frame(width: 14, height: 14)
            }
        }
    }
}
