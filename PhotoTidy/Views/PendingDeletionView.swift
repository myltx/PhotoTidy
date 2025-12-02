import SwiftUI

struct PendingDeletionView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showingConfirmAlert = false
    @State private var deleting = false
    @State private var deleteError: Error?
    @Environment(\.dismiss) private var dismiss

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
                    HStack(spacing: 4) {
                        Text("待删除")
                            .font(.title2).bold()
                        Text("(\(viewModel.pendingDeletionItems.count))")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
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
            Button("移至“最近删除”", role: .destructive) {
                deleting = true
                viewModel.performDeletion { success, error in
                    deleting = false
                    if success {
                        dismiss()
                    } else {
                        deleteError = error
                    }
                }
            }
        } message: {
            Text("这些照片将移动到系统“最近删除”相册。30 天内可在“照片 > 最近删除”恢复或彻底删除，超期将自动清除。")
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
        AssetThumbnailView(asset: item.asset, target: .dashboardCard)
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
                Text(releaseSizeText)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Button(action: {
                if !viewModel.pendingDeletionItems.isEmpty {
                    showingConfirmAlert = true
                }
            }) {
                ZStack {
                    Group {
                        if viewModel.pendingDeletionItems.isEmpty {
                            Color.gray.opacity(0.3)
                        } else {
                            LinearGradient(
                                colors: [Color("brand-start"), Color("brand-end")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack {
                        Image(systemName: "trash.fill")
                        Text("确认删除")
                    }
                    .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 55)
                .foregroundColor(.white)
            }
            .disabled(viewModel.pendingDeletionItems.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 34) // Safe area
        .background(.thinMaterial)
    }

    private var releaseSizeText: String {
        viewModel.pendingDeletionItems.isEmpty
        ? "--"
        : viewModel.pendingDeletionTotalSize.fileSizeDescription
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
