import SwiftUI
import Photos

struct TrashView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showingConfirmAlert = false
    @State private var isDeleting = false
    @State private var deleteError: Error?

    private var items: [PhotoItem] { viewModel.pendingDeletionItems }
    private var totalSizeText: String { viewModel.pendingDeletionTotalSize.fileSizeDescription }
    private var releaseSizeText: String { items.isEmpty ? "--" : totalSizeText }
    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGray6).ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        summary

                        if items.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 80)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(items, id: \.id) { item in
                                    TrashPreviewCell(item: item, viewModel: viewModel)
                                }
                            }
                            .padding(.top, 8)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                confirmSection
            }
            .navigationTitle("待删区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        items.forEach { viewModel.removeFromPending($0) }
                    }
                }
            }
        }
        .alert("确认删除这些照片？", isPresented: $showingConfirmAlert) {
            Button("取消", role: .cancel) {}
            Button("移至“最近删除”", role: .destructive) {
                startDeletion()
            }
        } message: {
            Text("这些照片将移动到系统“最近删除”相册。30 天内可在“照片 > 最近删除”中恢复或彻底删除。")
        }
        .alert("删除失败", isPresented: .constant(deleteError != nil), presenting: deleteError) { _ in
            Button("好的") { deleteError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var confirmSection: some View {
        VStack(spacing: 12) {
            confirmButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Color.clear)
    }

    private var summary: some View {
        HStack {
            Text("可释放 \(releaseSizeText)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 46))
                .foregroundColor(.secondary)
            Text("待删区为空")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 80)
    }

    private var confirmButton: some View {
        let isDisabled = items.isEmpty || isDeleting
        return Button(action: {
            if !isDisabled {
                showingConfirmAlert = true
            }
        }) {
            ZStack {
                Group {
                    if isDisabled {
                        Color.gray.opacity(0.3)
                    } else {
                        LinearGradient(
                            colors: [Color("brand-start"), Color("brand-end")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isDeleting ? "正在删除…" : "确认删除")
                            .font(.system(size: 15, weight: .bold))
                        Text("释放 \(releaseSizeText)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.horizontal, 18)
            }
            .frame(height: 56)
            .foregroundColor(.white)
        }
        .disabled(isDisabled)
    }

    private func startDeletion() {
        isDeleting = true
        viewModel.performDeletion { success, error in
            isDeleting = false
            if let error = error {
                deleteError = error
            }
        }
    }
}

private struct TrashPreviewCell: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
        AssetThumbnailView(
            asset: item.asset,
            imageManager: viewModel.imageManager,
            contentMode: .aspectFill
        )
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .cornerRadius(16)

            Button {
                viewModel.removeFromPending(item)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
            .padding(6)
        }
        .frame(height: 100)
    }
}
