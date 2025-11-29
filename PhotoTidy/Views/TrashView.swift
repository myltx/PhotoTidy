import SwiftUI
import Photos

struct TrashView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showingConfirmAlert = false
    @State private var showingClearAllAlert = false
    @State private var showPermissionEducationAlert = false
    @State private var isDeleting = false
    @State private var deleteError: Error?
    @Environment(\.dismiss) private var dismiss

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
            Color(UIColor.systemGray6)
                .overlay(
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
                        .padding(.bottom, 120)
                    }
                )
                .ignoresSafeArea()
            .navigationTitle("待删区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(UIColor.systemBackground))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingClearAllAlert = true
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(items.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !items.isEmpty {
                confirmToolbar
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .alert("清空待删区？", isPresented: $showingClearAllAlert) {
            Button("取消", role: .cancel) {}
            Button("确定清空", role: .destructive) {
                items.forEach { viewModel.removeFromPending($0) }
            }
        } message: {
            Text("将移除所有已选照片的待删标记，可在时间轴或首页重新选择。")
        }
        .alert("确认删除这些照片？", isPresented: $showingConfirmAlert) {
            Button("取消", role: .cancel) {}
            Button("移至“最近删除”", role: .destructive) {
                initiateDeletion()
            }
        } message: {
            Text("这些照片将移动到系统“最近删除”相册。30 天内可在“照片 > 最近删除”中恢复或彻底删除。")
        }
        .alert("需要完整照片权限", isPresented: $showPermissionEducationAlert) {
            Button("继续删除", role: .destructive) {
                startDeletion()
            }
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("由于您仅授予了“部分照片”权限，系统会在删除时再次向您确认。您可以在“设置”中开启“所有照片”权限以简化此流程。")
        }
        .alert("删除失败", isPresented: .constant(deleteError != nil), presenting: deleteError) { _ in
            Button("好的") { deleteError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
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

    private var confirmToolbar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选择 \(items.count) 项")
                    .font(.system(size: 13, weight: .semibold))
                Text("总计 \(totalSizeText)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showingConfirmAlert = true }) {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("确认删除")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color("brand-start"))
                .clipShape(Capsule())
            }
            .disabled(items.isEmpty || isDeleting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
    }
    
    private func initiateDeletion() {
        if viewModel.authorizationStatus == .limited {
            showPermissionEducationAlert = true
        } else {
            startDeletion()
        }
    }

    private func startDeletion() {
        isDeleting = true
        viewModel.performDeletion { success, error in
            isDeleting = false
            if let error = error, !success {
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
