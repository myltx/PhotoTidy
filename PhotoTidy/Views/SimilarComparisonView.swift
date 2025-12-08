import SwiftUI
import Photos

struct SimilarComparisonView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [SimilarGroup] = []
    @State private var selections: [Int: Set<String>] = [:]
    @State private var previewItem: PhotoItem?
    @State private var pendingRecomputeWorkItem: DispatchWorkItem?

    private let chipFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).ignoresSafeArea()

            VStack(spacing: 0) {
                ModalNavigationHeader(
                    title: "相似照片",
                    onClose: { dismiss() },
                    rightIcon: "arrow.clockwise",
                    onRightAction: recomputeGroups
                )

                if groups.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 18, pinnedViews: []) {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                groupCard(for: group, index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .onAppear(perform: recomputeGroups)
        .onChange(of: viewModel.items) { _ in
            scheduleRecomputeGroups()
        }
        .fullScreenCover(item: $previewItem) { item in
            FullScreenPreviewView(item: item, viewModel: viewModel)
        }
        .onDisappear(perform: cancelPendingRecompute)
    }

    // MARK: - UI Sections

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(Color("brand-start"))
            Text("暂无相似照片")
                .font(.headline)
            Text("我们会持续在后台扫描新的相似照片，保持图库整洁。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func groupCard(for group: SimilarGroup, index: Int) -> some View {
        let selected = selections[group.id] ?? []
        let recommendedItem = group.items[safe: group.recommendedIndex]
        let dateText = recommendedItem?.creationDate.flatMap { chipFormatter.string(from: $0) } ?? "未知日期"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(index + 1) 组")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(dateText) • 共 \(group.items.count) 张")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                recommendedBadge(for: recommendedItem)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(group.items) { item in
                        selectableThumbnail(for: item, in: group)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 12) {
                Button {
                    skip(group: group)
                } label: {
                    Label("跳过本组", systemImage: "arrow.uturn.right")
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button {
                    applySelection(for: group)
                } label: {
                    let keepCount = selected.count
                    Label("保留所选 (\(keepCount))", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }

    private func selectableThumbnail(for item: PhotoItem, in group: SimilarGroup) -> some View {
        let selectedIds = selections[group.id] ?? []
        let isSelected = selectedIds.contains(item.id)
        let recommendedId = group.items[group.recommendedIndex].id
        let isRecommended = item.id == recommendedId

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AssetThumbnailView(
                    asset: item.asset,
                    imageManager: viewModel.imageManager,
                    contentMode: .aspectFill
                )
                .frame(width: 90, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color("brand-start") : Color.clear, lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(isSelected ? 0.2 : 0.05), radius: isSelected ? 8 : 3, y: isSelected ? 4 : 2)
                .onTapGesture {
                    previewItem = item
                }

                VStack(alignment: .trailing, spacing: 6) {
                    if isRecommended {
                        Text("推荐")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.9))
                            .clipShape(Capsule())
                            .foregroundColor(.white)
                            .padding([.top, .trailing], 6)
                    } else {
                        Color.clear.frame(height: 0)
                    }

                    Spacer()

                    Button {
                        toggleSelection(for: item, in: group)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? Color("brand-start") : Color.white)
                            .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
                            .padding(8)
                    }
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
                    .padding(6)
                }
            }

            Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(width: 100)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private func recommendedBadge(for item: PhotoItem?) -> some View {
        if let item {
            Label("推荐保留", systemImage: "star.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.yellow.opacity(0.15))
                )
                .foregroundColor(Color("brand-start"))
                .overlay(
                    Capsule()
                        .stroke(Color("brand-start").opacity(0.3), lineWidth: 1)
                )
                .accessibilityLabel("推荐保留 \(item.asset.originalFilename)")
        }
    }

    // MARK: - Actions

    private func toggleSelection(for item: PhotoItem, in group: SimilarGroup) {
        var current = selections[group.id] ?? []
        if current.contains(item.id) {
            if current.count > 1 {
                current.remove(item.id)
            }
        } else {
            current.insert(item.id)
        }
        if current.isEmpty {
            let fallback = group.items[group.recommendedIndex].id
            current.insert(fallback)
        }
        selections[group.id] = current
    }

    private func skip(group: SimilarGroup) {
        if let recommended = group.items[safe: group.recommendedIndex] {
            viewModel.logSkippedPhoto(recommended, source: .similarGroup)
        }
        removeGroup(group.id)
    }

    private func applySelection(for group: SimilarGroup) {
        let keepIds = selections[group.id] ?? [group.items[group.recommendedIndex].id]
        for item in group.items {
            viewModel.setDeletion(item, to: !keepIds.contains(item.id))
        }
        removeGroup(group.id)
    }

    private func removeGroup(_ id: Int) {
        withAnimation {
            groups.removeAll { $0.id == id }
            selections.removeValue(forKey: id)
        }
        if groups.isEmpty {
            scheduleRecomputeGroups(after: 0.4)
        }
    }

    // MARK: - Data Preparation

    private func recomputeGroups() {
        cancelPendingRecompute()
        var buckets: [Int: [PhotoItem]] = [:]
        var seenPerGroup: [Int: Set<String>] = [:]

        for item in viewModel.items {
            guard let groupId = item.similarGroupId else { continue }
            var seen = seenPerGroup[groupId] ?? []
            if seen.contains(item.id) { continue }
            seen.insert(item.id)
            seenPerGroup[groupId] = seen
            buckets[groupId, default: []].append(item)
        }

        var nextGroups: [SimilarGroup] = []
        var nextSelections: [Int: Set<String>] = [:]

        for (groupId, items) in buckets {
            let sorted = items.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            guard !sorted.isEmpty else { continue }
            let recommended = recommendedIndex(for: sorted)
            let latestDate = sorted.first?.creationDate ?? .distantPast
            nextGroups.append(
                SimilarGroup(
                    id: groupId,
                    items: sorted,
                    recommendedIndex: recommended,
                    latestDate: latestDate
                )
            )

            let availableIds = Set(sorted.map(\.id))
            if let existing = selections[groupId]?.intersection(availableIds), !existing.isEmpty {
                nextSelections[groupId] = existing
            } else {
                nextSelections[groupId] = [sorted[recommended].id]
            }
        }

        groups = nextGroups.sorted { $0.latestDate > $1.latestDate }
        selections = nextSelections
    }

    private func scheduleRecomputeGroups(after delay: TimeInterval = 0.35) {
        cancelPendingRecompute()
        let work = DispatchWorkItem { self.recomputeGroups() }
        pendingRecomputeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingRecompute() {
        pendingRecomputeWorkItem?.cancel()
        pendingRecomputeWorkItem = nil
    }

    private func recommendedIndex(for group: [PhotoItem]) -> Int {
        guard !group.isEmpty else { return 0 }
        var bestIndex = 0
        var bestScore = -Double.infinity
        for (index, item) in group.enumerated() {
            let blurScore = item.blurScore ?? 0
            let exposurePenalty = item.exposureIsBad ? -0.5 : 0
            let score = blurScore + exposurePenalty
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }
}

// MARK: - Models & Styles

private struct SimilarGroup: Identifiable {
    let id: Int
    let items: [PhotoItem]
    let recommendedIndex: Int
    let latestDate: Date
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                LinearGradient(
                    colors: [Color("brand-start"), Color("brand-end")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.systemGray5))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
