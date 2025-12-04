import SwiftUI

struct DecisionCenterView: View {
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    @StateObject private var pendingViewModel = PhotoFeedViewModel(intent: .pending(kind: .pendingDeletion))
    @StateObject private var skippedViewModel = PhotoFeedViewModel(intent: .pending(kind: .skipped))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("请选择需要处理的队列，查看详情并执行操作。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                NavigationLink {
                    DecisionListView(
                        title: "待删区",
                        description: "管理准备删除的照片",
                        viewModel: pendingViewModel,
                        accent: .red,
                        mode: .pendingDeletion,
                        onVisibilityChange: onDetailVisibilityChange
                    )
                } label: {
                    DecisionEntryCard(
                        iconName: "trash",
                        title: "待删区",
                        subtitle: "准备删除的记录",
                        count: assetCount(for: pendingViewModel),
                        accent: .red
                    )
                }

                NavigationLink {
                    DecisionListView(
                        title: "待确认图片",
                        description: "已跳过、待确认的记录",
                        viewModel: skippedViewModel,
                        accent: .blue,
                        mode: .skipped,
                        onVisibilityChange: onDetailVisibilityChange
                    )
                } label: {
                    DecisionEntryCard(
                        iconName: "questionmark.circle",
                        title: "待确认",
                        subtitle: "跳过暂存的记录",
                        count: assetCount(for: skippedViewModel),
                        accent: .blue
                    )
                }
            }
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("决策中心")
    }

    private func assetCount(for viewModel: PhotoFeedViewModel) -> Int {
        viewModel.state.items.filter {
            if case .asset = $0.payload { return true }
            return false
        }.count
    }
}

private struct DecisionListView: View {
    enum Mode {
        case pendingDeletion
        case skipped
    }

    @Environment(\.dismiss) private var dismiss

    let title: String
    let description: String
    @ObservedObject var viewModel: PhotoFeedViewModel
    let accent: Color
    let mode: Mode
    let onVisibilityChange: (Bool) -> Void

    @State private var selection: Set<String> = []
    @State private var hiddenIds: Set<String> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showSelectionDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if mode == .skipped {
                    selectionToolbar
                }

                gridSection
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear { onVisibilityChange(true) }
        .onDisappear { onVisibilityChange(false) }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            if mode == .pendingDeletion && !assetItems.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showBulkDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash.slash")
                    }
                    .tint(.red)
                    .accessibilityLabel("删除全部")
                }
            }
        }
        .confirmationDialog("确认删除全部待删照片？", isPresented: $showBulkDeleteConfirm) {
            Button("删除全部", role: .destructive) {
                performBulkDelete()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("确认删除所选照片？", isPresented: $showSelectionDeleteConfirm) {
            Button("删除所选", role: .destructive) {
                performDeleteSelection()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 5)
    }

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("共 \(assetItems.count) 张")
                    .foregroundColor(.secondary)
                if selection.count > 0 {
                    Text("已选 \(selection.count) 张")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Button("清除选择") {
                        selection.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(assetItems) { item in
                    if let metadata = metadata(for: item) {
                        DecisionGridTile(
                            metadata: metadata,
                            isSelected: selection.contains(item.id)
                        )
                        .onTapGesture {
                            toggleSelection(item.id)
                        }
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selection)
                    }
                }
            }

            if viewModel.state.cursor != nil {
                Button("加载更多") {
                    viewModel.requestNextPage()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var selectionToolbar: some View {
        VStack(spacing: 12) {
            Text("勾选需要处理的照片，可批量执行操作。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                DecisionActionButton(
                    systemName: "arrow.uturn.left",
                    title: "放回",
                    tint: .orange,
                    disabled: selection.isEmpty,
                    action: performReturnToFlow
                )
                DecisionActionButton(
                    systemName: "trash",
                    title: "删除",
                    tint: .red,
                    disabled: selection.isEmpty,
                    action: { showSelectionDeleteConfirm = true }
                )
                DecisionActionButton(
                    systemName: "checkmark.seal",
                    title: "保留",
                    tint: accent,
                    disabled: selection.isEmpty,
                    action: performConfirmKeep
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var assetItems: [PhotoFeedItem] {
        viewModel.state.items.compactMap { item in
            guard case .asset = item.payload, !hiddenIds.contains(item.id) else { return nil }
            return item
        }
    }

    private func metadata(for item: PhotoFeedItem) -> PhotoAssetMetadata? {
        if case let .asset(asset) = item.payload {
            return asset
        }
        return nil
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func performBulkDelete() {
        let ids = Set(assetItems.map(\.id))
        hiddenIds.formUnion(ids)
        selection.subtract(ids)
        // TODO: 接入真实删除逻辑
    }

    private func performDeleteSelection() {
        hiddenIds.formUnion(selection)
        selection.removeAll()
        // TODO: 接入真实删除逻辑
    }

    private func performReturnToFlow() {
        hiddenIds.formUnion(selection)
        selection.removeAll()
        // TODO: 写回主流程
    }

    private func performConfirmKeep() {
        hiddenIds.formUnion(selection)
        selection.removeAll()
        // TODO: 记录保留结果
    }
}

private struct DecisionEntryCard: View {
    let iconName: String
    let title: String
    let subtitle: String
    let count: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing) {
                Text("\(count)")
                    .font(.title3.bold())
                    .foregroundColor(accent)
                Text("条记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
}

private struct DecisionGridTile: View {
    let metadata: PhotoAssetMetadata
    let isSelected: Bool

    private let tileSize: CGFloat = 72

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AssetPreviewView(metadata: metadata, cornerRadius: 12, showOverlay: false)
                .frame(height: tileSize)
                .clipped()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .padding(6)
                    .shadow(radius: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DecisionActionButton: View {
    let systemName: String
    let title: String
    let tint: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(disabled ? .white.opacity(0.4) : .white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(tint)
                            .opacity(disabled ? 0.3 : 1)
                    )
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(disabled)
    }
}
