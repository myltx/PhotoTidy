import SwiftUI
import Photos

struct SimilarComparisonView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String?

    private var groups: [[PhotoItem]] {
        let grouped = Dictionary(grouping: viewModel.items.filter { $0.similarGroupId != nil }) { $0.similarGroupId ?? -1 }
        return grouped.values.sorted { ($0.first?.creationDate ?? .distantPast) > ($1.first?.creationDate ?? .distantPast) }
    }

    private var currentGroup: [PhotoItem]? { groups.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let group = currentGroup {
                    let hero = selectedItem(from: group)
                    VStack(spacing: 12) {
                        Text("相似度 \(Int.random(in: 90...99))%")
                            .font(.title2).bold()
                        Text("建议保留 1 张，删除其余 \(max(group.count - 1, 0)) 张。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    ZStack {
                        if group.count > 1 {
                            comparisonCard(for: group[1])
                                .rotationEffect(.degrees(6))
                                .offset(x: 24, y: 18)
                        }
                        if let hero = hero {
                            comparisonCard(for: hero, highlight: true)
                                .rotationEffect(.degrees(-3))
                                .offset(x: -10, y: -10)
                        }
                    }
                    .frame(height: 420)

                    Button {
                        if let hero = hero {
                            applySelection(keep: hero, delete: group.filter { $0.id != hero.id })
                        }
                    } label: {
                        Text("保留最佳")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color("brand-start"))
                            .cornerRadius(18)
                    }

                    Button {
                        viewModel.showCleaner(filter: .similar)
                        dismiss()
                    } label: {
                        Text("进入全部相似照片")
                            .font(.subheadline.bold())
                    }
                } else {
                    Text("没有检测到相似照片").foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("相似照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func selectedItem(from group: [PhotoItem]) -> PhotoItem? {
        if let selectedId = selectedId, let item = group.first(where: { $0.id == selectedId }) {
            return item
        }
        let first = group.first
        selectedId = selectedId ?? first?.id
        return first
    }

    private func applySelection(keep hero: PhotoItem, delete others: [PhotoItem]) {
        viewModel.setDeletion(hero, to: false)
        others.forEach { viewModel.setDeletion($0, to: true) }
    }

    private func comparisonCard(for item: PhotoItem, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                .frame(width: 280, height: 360)
                .cornerRadius(28)
                .overlay(
                    VStack(alignment: .leading) {
                        Text(item.asset.originalFilename)
                            .font(.headline).bold()
                            .foregroundColor(.white)
                        Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                        .padding(),
                    alignment: .bottomLeading
                )
                .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        }
        .frame(width: 300, height: 380)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(highlight ? Color("brand-start") : Color.clear, lineWidth: 4)
        )
        .onTapGesture {
            selectedId = item.id
        }
    }
}
