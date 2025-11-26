import SwiftUI
import Photos

struct BlurryReviewView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<String> = []

    private var blurryItems: [PhotoItem] {
        viewModel.items.filter { $0.isBlurredOrShaky || $0.exposureIsBad }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if blurryItems.isEmpty {
                    Spacer()
                    Text("暂无模糊照片").foregroundColor(.secondary)
                    Spacer()
                } else {
                    blurSummary
                    blurryGrid
                    deleteButton
                }
            }
            .padding()
            .navigationTitle("模糊照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                selectedIds = Set(blurryItems.map(\.id))
            }
        }
    }

    private var blurSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("已选中 \(selectedIds.count) 张")
                    .font(.headline)
                Text("建议删除模糊、曝光异常的照片").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("全选") { selectedIds = Set(blurryItems.map(\.id)) }
                .font(.subheadline.bold())
        }
    }

    private var blurryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(blurryItems, id: \.id) { item in
                    ZStack(alignment: .topTrailing) {
                        AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                            .aspectRatio(1, contentMode: .fit)
                            .cornerRadius(20)
                            .overlay(
                                VStack(alignment: .leading) {
                                    Text(item.isBlurredOrShaky ? "模糊" : "曝光")
                                        .font(.caption2).bold()
                                        .padding(6)
                                        .background(Color.red.opacity(0.8))
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                                    .padding(8),
                                alignment: .bottomLeading
                            )
                        Button(action: { toggleSelection(item) }) {
                            Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(selectedIds.contains(item.id) ? Color("brand-start") : .white)
                                .padding(10)
                        }
                    }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button {
            applyDeletion()
        } label: {
            Text("删除选中 (\(selectedIds.count))")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedIds.isEmpty ? Color.gray : Color.red)
                .cornerRadius(22)
        }
        .disabled(selectedIds.isEmpty)
    }

    private func toggleSelection(_ item: PhotoItem) {
        if selectedIds.contains(item.id) {
            selectedIds.remove(item.id)
        } else {
            selectedIds.insert(item.id)
        }
    }

    private func applyDeletion() {
        blurryItems.forEach { item in
            viewModel.setDeletion(item, to: selectedIds.contains(item.id))
        }
        dismiss()
    }
}
