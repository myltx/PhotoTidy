import SwiftUI
import Photos

struct BlurryReviewView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<String> = []
    @State private var previewItem: PhotoItem?

    private var blurryItems: [PhotoItem] {
        viewModel.items.filter { $0.isBlurredOrShaky || $0.exposureIsBad }
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ModalNavigationHeader(
                    title: "模糊照片",
                    onClose: { dismiss() }
                )

                headerSection

                if blurryItems.isEmpty {
                    Spacer()
                    Text("暂无模糊或曝光异常照片")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    blurryGrid

                    deleteButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .onAppear {
            selectedIds = Set(blurryItems.map(\.id))
        }
        .fullScreenCover(item: $previewItem) { item in
            FullScreenPreviewView(item: item, viewModel: viewModel)
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("已选中 \(selectedIds.count) 张")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text("建议删除模糊、曝光异常的照片")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                selectedIds = Set(blurryItems.map(\.id))
            }) {
                Text("全选")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color("brand-start"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var blurryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(blurryItems, id: \.id) { item in
                    let isSelected = selectedIds.contains(item.id)

                    ZStack(alignment: .topTrailing) {
                        ZStack(alignment: .bottomLeading) {
                            AssetThumbnailView(
                                asset: item.asset,
                                imageManager: viewModel.imageManager,
                                contentMode: .aspectFill
                            )
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .opacity(isSelected ? 1.0 : 0.5)

                            if item.isBlurredOrShaky || item.exposureIsBad {
                                Text(item.isBlurredOrShaky ? "模糊" : "曝光不足")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        (item.isBlurredOrShaky ? Color.red : Color.black)
                                            .opacity(0.8)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .padding(8)
                            }
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Button(action: { toggleSelection(item) }) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? Color("brand-start") : Color.white.opacity(0.9))
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected ? Color("brand-start") : Color(UIColor.systemGray4), lineWidth: 1)
                                    )
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            previewItem = item
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 24, height: 24)
                            .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var deleteButton: some View {
        Button {
            applyDeletion()
        } label: {
            Text("删除选中 (\(selectedIds.count))")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(selectedIds.isEmpty ? .gray : .red)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(selectedIds.isEmpty ? Color(UIColor.systemGray5) : Color.red.opacity(0.08))
                )
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
