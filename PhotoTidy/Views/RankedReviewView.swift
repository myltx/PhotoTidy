import SwiftUI

struct RankedReviewView: View {
    @State private var selectedKind: PhotoRankedKind = .largeFiles

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("专项", selection: $selectedKind) {
                    Text("大文件").tag(PhotoRankedKind.largeFiles)
                    Text("模糊").tag(PhotoRankedKind.blurred)
                    Text("文档").tag(PhotoRankedKind.documents)
                    Text("截图").tag(PhotoRankedKind.screenshots)
                }
                .pickerStyle(.segmented)

                RankedFeedSection(kind: selectedKind)
                    .id(selectedKind)
            }
            .padding(20)
            .navigationTitle("专项处理")
            .background(Color(.systemGroupedBackground))
        }
    }
}

private struct RankedFeedSection: View {
    let kind: PhotoRankedKind
    @StateObject private var viewModel: PhotoFeedViewModel
    @State private var selectedAssetIds: Set<String> = []

    init(kind: PhotoRankedKind) {
        self.kind = kind
        _viewModel = StateObject(wrappedValue: PhotoFeedViewModel(intent: .ranked(kind: kind)))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                ForEach(assetItems) { item in
                    RankedSelectableCard(
                        item: item,
                        kind: kind,
                        isSelected: isSelected(item),
                        onToggle: { toggleSelection(for: item) }
                    )
                }
            }
            .padding(.vertical, 4)
            if !selectedAssetIds.isEmpty {
                Text("已选择 \(selectedAssetIds.count) 张，稍后将加入待删区")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
            if viewModel.state.cursor != nil {
                Button("更多") {
                    viewModel.requestNextPage()
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
    }

    private var assetItems: [PhotoFeedItem] {
        viewModel.state.items.filter {
            if case .asset = $0.payload { return true }
            return false
        }
    }

    private func assetId(from item: PhotoFeedItem) -> String? {
        if case let .asset(asset) = item.payload {
            return asset.id
        }
        return nil
    }

    private func isSelected(_ item: PhotoFeedItem) -> Bool {
        guard let id = assetId(from: item) else { return false }
        return selectedAssetIds.contains(id)
    }

    private func toggleSelection(for item: PhotoFeedItem) {
        guard let id = assetId(from: item) else { return }
        if selectedAssetIds.contains(id) {
            selectedAssetIds.remove(id)
            PhotoStoreFacade.shared.applyDecision(assetIds: [id], newState: .clean)
        } else {
            selectedAssetIds.insert(id)
            PhotoStoreFacade.shared.applyDecision(assetIds: [id], newState: .pendingDeletion)
        }
    }
}

private struct RankedSelectableCard: View {
    let item: PhotoFeedItem
    let kind: PhotoRankedKind
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let metadata {
                AssetPreviewView(metadata: metadata, cornerRadius: 18)
                    .frame(height: 140)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(item.thumbnail.palette.gradient)
                    .frame(height: 140)
            }
            Text(kindTitle)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            onToggle()
        }
    }

    private var metadata: PhotoAssetMetadata? {
        if case let .asset(asset) = item.payload {
            return asset
        }
        return nil
    }

    private var kindTitle: String {
        switch kind {
        case .largeFiles:
            return "\(metadata?.formattedSize ?? "")"
        case .blurred:
            return "模糊评分 \(String(format: "%.0f%%", (metadata?.blurScore ?? 0) * 100))"
        case .documents:
            return "文档评分 \(String(format: "%.0f%%", (metadata?.documentScore ?? 0) * 100))"
        case .screenshots:
            return "截图"
        }
    }

    private var detail: String {
        guard let metadata else { return "" }
        return metadata.captureDate.formatted(date: .abbreviated, time: .omitted)
    }
}
