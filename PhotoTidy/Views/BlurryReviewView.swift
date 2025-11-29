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
                }
            }
        }
        .fullScreenCover(item: $previewItem) { item in
            FullScreenPreviewView(item: item, viewModel: viewModel)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if blurryItems.isEmpty {
                    Color.clear.frame(height: 0)
                } else {
                    blurryToolbar
                }
            }
        }
    }

    private var headerSection: some View {
        HStack {
            Text("建议删除模糊、曝光异常的照片")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: toggleSelectAll) {
                Text(allSelected ? "取消全选" : "全选")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color("brand-start"))
            }
            .disabled(blurryItems.isEmpty)
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(isSelected ? Color("brand-start").opacity(0.6) : Color.clear, lineWidth: 1)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(isSelected ? Color("brand-start").opacity(0.12) : Color.clear)
                        )

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

    private var allSelected: Bool {
        !blurryItems.isEmpty && selectedIds.count == blurryItems.count
    }

    private var selectedCount: Int { selectedIds.count }
    
    private var blurryToolbar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选择 \(selectedCount) 张")
                    .font(.system(size: 13, weight: .semibold))
                Text("确认后移动至待删区")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                applyDeletion()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("删除选中")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(selectedCount == 0 ? Color.gray : Color("brand-start"))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
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

    private func toggleSelectAll() {
        if allSelected {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(blurryItems.map(\.id))
        }
    }
}
