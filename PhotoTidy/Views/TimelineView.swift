import SwiftUI

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @State private var selectedBucket: TimelineBucketSnapshot?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(viewModel.yearSections, id: \.year) { section in
                        YearSectionView(section: section, action: { bucket in
                            selectedBucket = bucket
                        })
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("时光机")
        }
        .sheet(item: $selectedBucket) { bucket in
            MonthDetailView(bucket: bucket)
        }
    }
}

private struct YearSectionView: View {
    let section: TimelineViewModel.YearSectionModel
    let action: (TimelineBucketSnapshot) -> Void

    private var rows: [[TimelineBucketSnapshot]] {
        stride(from: 0, to: section.months.count, by: 6).map { index in
            Array(section.months[index..<min(index + 6, section.months.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(section.year)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(rows, id: \.self) { row in
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(row) { bucket in
                        Button {
                            action(bucket)
                        } label: {
                            MonthMiniCard(bucket: bucket)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct MonthMiniCard: View {
    let bucket: TimelineBucketSnapshot

    var body: some View {
        VStack(spacing: 6) {
            if let cover = bucket.cover {
                AssetPreviewView(metadata: cover, cornerRadius: 12, showOverlay: false)
                    .frame(height: 60)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill((bucket.cover?.palette ?? ThumbnailPalette(startHex: "#777", endHex: "#444")).gradient)
                    .frame(height: 60)
            }
            VStack(spacing: 2) {
                Text(monthTitle)
                    .font(.caption2.bold())
                    .lineLimit(1)
                Text("\(bucket.assetCount) 张")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var monthTitle: String {
        "\(bucket.monthKey.month)月"
    }
}

private struct MonthDetailView: View {
    let bucket: TimelineBucketSnapshot
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PhotoFeedViewModel
    @State private var selectedAssetIds: Set<String> = []

    init(bucket: TimelineBucketSnapshot) {
        self.bucket = bucket
        _viewModel = StateObject(wrappedValue: PhotoFeedViewModel(intent: .sequential(scope: .month(bucket.monthKey))))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(viewModel.state.items) { item in
                        if case .asset = item.payload {
                            MonthSelectableCell(
                                item: item,
                                isSelected: isSelected(item),
                                onToggle: { toggleSelection(item) }
                            )
                        }
                    }
                }
                .padding()
                if !selectedAssetIds.isEmpty {
                    Text("已选择 \(selectedAssetIds.count) 张，将加入待删区")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.bottom)
                }
            }
            .navigationTitle(bucket.monthKey.title)
            .toolbar {
                Button("关闭") { dismiss() }
            }
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

    private func toggleSelection(_ item: PhotoFeedItem) {
        guard let id = assetId(from: item) else { return }
        if selectedAssetIds.contains(id) {
            selectedAssetIds.remove(id)
        } else {
            selectedAssetIds.insert(id)
        }
    }
}

private struct MonthSelectableCell: View {
    let item: PhotoFeedItem
    let isSelected: Bool
    let onToggle: () -> Void

    private var metadata: PhotoAssetMetadata? {
        if case let .asset(asset) = item.payload {
            return asset
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let metadata {
                AssetPreviewView(metadata: metadata, cornerRadius: 12)
                    .frame(height: 110)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.thumbnail.palette.gradient)
                    .frame(height: 110)
            }
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .padding(6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onToggle()
        }
    }
}
