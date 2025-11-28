import SwiftUI
import Photos

struct TrashView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showingConfirmAlert = false
    @State private var showPermissionEducationAlert = false
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
            ZStack(alignment: .bottom) {
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
                    .padding(.bottom, 150)
                }

                if !items.isEmpty {
                    floatingConfirmButton
                        .padding(.bottom, 65)
                }
            }
            .navigationTitle("待删区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        items.forEach { viewModel.removeFromPending($0) }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(items.isEmpty)
                }
            }
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

    private var floatingConfirmButton: some View {
        Button(action: {
            showingConfirmAlert = true
        }) {
            HStack {
                Image(systemName: "trash.fill")
                Text("确认删除 (\(items.count))")
            }
            .font(.headline.weight(.bold))
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color("brand-start"))
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(color: Color("brand-start").opacity(0.3), radius: 10, y: 5)
        }
        .padding(.horizontal, 24)
        .disabled(items.isEmpty || isDeleting)
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
