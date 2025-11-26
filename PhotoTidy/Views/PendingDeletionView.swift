import SwiftUI

struct PendingDeletionView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showingConfirmAlert = false
    @State private var deleting = false
    @State private var deleteError: Error?

    var body: some View {
        VStack(spacing: 0) {
            // Handle for modal presentation
            VStack {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                // Header
                HStack {
                    Text("待删除")
                        .font(.title2).bold()
                    +
                    Text(" (\(viewModel.pendingDeletionItems.count))")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("关闭") {
                        viewModel.hideTrash()
                    }
                    .font(.body).foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .background(Color(UIColor.systemGray6))

            // Content
            ZStack {
                Color(UIColor.systemGray6).edgesIgnoringSafeArea(.all)
                
                if viewModel.pendingDeletionItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                            ForEach(viewModel.pendingDeletionItems) { item in
                                TrashItemView(item: item, viewModel: viewModel)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                        .padding(.bottom, 150)
                    }
                }
                
                VStack {
                    Spacer()
                    TrashActionsView(viewModel: viewModel, showingConfirmAlert: $showingConfirmAlert)
                }
            }
        }
        .background(Color(UIColor.systemGray6))
        .frame(maxHeight: .infinity)
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.15), radius: 20, y: -10)
        .alert("确认删除这些照片？", isPresented: $showingConfirmAlert) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                deleting = true
                viewModel.performDeletion { success, error in
                    deleting = false
                    if success {
                        viewModel.hideTrash()
                    } else {
                        deleteError = error
                    }
                }
            }
        } message: {
            Text("将从系统相册中永久删除这些照片或视频，此操作无法恢复。")
        }
        .alert("删除失败", isPresented: .constant(deleteError != nil), presenting: deleteError) { _ in
            Button("好的") { deleteError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
    
    private var emptyState: some View {
        VStack {
            Image(systemName: "trash.circle")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.4))
            Text("待删区是空的")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }
}

private struct TrashItemView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(
                ZStack(alignment: .topTrailing) {
                    // Remove button
                    Button(action: {
                        withAnimation {
                            viewModel.removeFromPending(item)
                        }
                    }) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .padding(6)
                }
            )
    }
}

private struct TrashActionsView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Binding var showingConfirmAlert: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("预计释放空间")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Text(viewModel.pendingDeletionTotalSize.fileSizeDescription)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Button(action: {
                if !viewModel.pendingDeletionItems.isEmpty {
                    showingConfirmAlert = true
                }
            }) {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("确认删除")
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 55)
                .background(viewModel.pendingDeletionItems.isEmpty ? Color.gray : Color.black)
                .foregroundColor(.white)
                .cornerRadius(16)
            }
            .disabled(viewModel.pendingDeletionItems.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 34) // Safe area
        .background(.thinMaterial)
    }
}

// Helper for rounding specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
