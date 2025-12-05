import SwiftUI

struct GroupedReviewView: View {
    var body: some View {
        NavigationStack {
            GroupFeedSection()
                .padding(16)
                .navigationTitle("相似照片")
                .background(Color(.systemGroupedBackground))
        }
    }
}

private struct GroupFeedSection: View {
    @StateObject private var viewModel = PhotoFeedViewModel(intent: .grouped(kind: .similar))
    @State private var selections: [String: Set<String>] = [:]
    @State private var groupStates: [String: GroupActionState] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(groupItems, id: \.id) { item in
                    if case let .group(group) = item.payload {
                        let binding = Binding<Set<String>>(
                            get: { selections[group.id] ?? defaultSelection(for: group) },
                            set: { selections[group.id] = $0 }
                        )
                        SimilarGroupCard(
                            group: group,
                            selection: binding,
                            state: groupStates[group.id] ?? .idle,
                            onSkip: {
                                handleSkip(group: group)
                            },
                            onConfirm: { ids in
                                handleConfirm(group: group, keep: ids)
                            }
                        )
                    }
                }
                if viewModel.state.cursor != nil {
                    Button("加载更多") {
                        viewModel.requestNextPage()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.vertical)
                }
            }
        }
    }

    private var groupItems: [PhotoFeedItem] {
        viewModel.state.items.filter {
            if case .group = $0.payload { return true }
            return false
        }
    }

    private func defaultSelection(for group: PhotoGroupSnapshot) -> Set<String> {
        let recommended = group.members.max(by: { $0.similarityScore < $1.similarityScore })?.id
        return recommended.map { [$0] } ?? []
    }

    private func markGroup(_ id: String, as state: GroupActionState) {
        withAnimation {
            groupStates[id] = state
        }
    }

    private func handleSkip(group: PhotoGroupSnapshot) {
        let ids = group.members.map(\.id)
        guard !ids.isEmpty else { return }
        PhotoStoreFacade.shared.applyDecision(assetIds: ids, newState: .skipped)
        markGroup(group.id, as: .skipped)
    }

    private func handleConfirm(group: PhotoGroupSnapshot, keep ids: Set<String>) {
        let allIds = group.members.map(\.id)
        let keepIds = allIds.filter { ids.contains($0) }
        let deleteIds = allIds.filter { !ids.contains($0) }
        if !keepIds.isEmpty {
            PhotoStoreFacade.shared.applyDecision(assetIds: keepIds, newState: .clean)
        }
        if !deleteIds.isEmpty {
            PhotoStoreFacade.shared.applyDecision(assetIds: deleteIds, newState: .pendingDeletion)
        }
        markGroup(group.id, as: .completed(kept: keepIds.count, deleted: deleteIds.count))
    }
}

private struct SimilarGroupCard: View {
    let group: PhotoGroupSnapshot
    @Binding var selection: Set<String>
    let state: GroupActionState
    let onSkip: () -> Void
    let onConfirm: (Set<String>) -> Void

    private var recommendedId: String? {
        group.members.max(by: { $0.similarityScore < $1.similarityScore })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(group.members, id: \.id) { member in
                        SelectableAssetCell(
                            metadata: member,
                            isSelected: selection.contains(member.id),
                            isRecommended: member.id == recommendedId
                        )
                        .onTapGesture {
                            toggle(member.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 2)
            if let message = state.message {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(state.tint)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(group.displayName)
                    .font(.title3.bold())
                Text("包含 \(group.members.count) 张 • 置信 \(String(format: "%.0f%%", group.confidence * 100))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                ControlIcon(systemName: "checkmark.circle", tint: .accentColor) {
                    selection = Set(group.members.map { $0.id })
                }
                .disabled(state.isCompleted)

                ControlIcon(systemName: "tray.and.arrow.down", tint: .blue) {
                    onConfirm(selection)
                }
                .disabled(selection.isEmpty || state.isCompleted)

                ControlIcon(systemName: "arrow.uturn.up", tint: .red) {
                    selection = []
                    onSkip()
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

private struct SelectableAssetCell: View {
    let metadata: PhotoAssetMetadata
    let isSelected: Bool
    let isRecommended: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AssetPreviewView(metadata: metadata, cornerRadius: 16)
                .frame(width: 120, height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
            if isRecommended {
                Label("推荐", systemImage: "star.fill")
                    .font(.caption2.bold())
                    .padding(6)
                    .background(Color.yellow.opacity(0.9), in: Capsule())
                    .foregroundColor(.white)
                    .padding(6)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .padding(8)
            }
        }
    }
}

private struct ControlIcon: View {
    let systemName: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundColor(.white)
                .padding(10)
                .background(tint.gradient, in: Circle())
                .shadow(color: tint.opacity(0.3), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct GroupActionState: Equatable {
    enum Status: Equatable {
        case idle
        case skipped
        case completed(kept: Int, deleted: Int)
    }

    var status: Status = .idle

    static var idle: GroupActionState { GroupActionState() }
    static var skipped: GroupActionState { GroupActionState(status: .skipped) }
    static func completed(kept: Int, deleted: Int) -> GroupActionState {
        GroupActionState(status: .completed(kept: kept, deleted: deleted))
    }

    var message: String? {
        switch status {
        case .idle:
            return nil
        case .skipped:
            return "已跳过此组，稍后可在待确认中查看。"
        case let .completed(kept, deleted):
            return "已保留 \(kept) 张，\(deleted) 张加入待删区。"
        }
    }

    var tint: Color {
        switch status {
        case .idle:
            return .secondary
        case .skipped:
            return .orange
        case .completed:
            return .green
        }
    }

    var isCompleted: Bool {
        switch status {
        case .completed, .skipped:
            return true
        default:
            return false
        }
    }
}
