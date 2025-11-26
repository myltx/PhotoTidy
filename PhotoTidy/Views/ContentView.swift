import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var viewModel = PhotoCleanupViewModel()

    var body: some View {
        ZStack {
            switch viewModel.authorizationStatus {
            case .authorized, .limited:
                MainAppView(viewModel: viewModel)
            case .denied, .restricted:
                PermissionDeniedView()
            case .notDetermined:
                PermissionRequestView(viewModel: viewModel)
            @unknown default:
                Text("未知相册权限状态")
            }
        }
        .onAppear {
            if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                viewModel.loadAssets()
            }
        }
    }
}

// MARK: - Main App View Structure
struct MainAppView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        ZStack {
            // Main content based on tab
            VStack {
                if viewModel.currentTab == .dashboard {
                    DashboardView(viewModel: viewModel)
                } else if viewModel.currentTab == .album {
                    AlbumGridView(viewModel: viewModel)
                } else {
                    SettingsView(viewModel: viewModel)
                }
            }
            .zIndex(0)

            // Bottom Navigation
            VStack {
                Spacer()
                BottomNavBar(viewModel: viewModel)
            }
            .zIndex(2)
            .transition(.move(edge: .bottom))
            .opacity(viewModel.isShowingCleaner ? 0 : 1)

            // Cleaner View (Slides over everything)
            if viewModel.isShowingCleaner {
                CleanerContainerView(viewModel: viewModel)
                    .zIndex(3)
                    .transition(.move(edge: .trailing))
            }
            
            // Pending Deletion View (Slides up)
            if viewModel.isShowingTrash {
                PendingDeletionView(viewModel: viewModel)
                    .zIndex(4)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isShowingCleaner)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.isShowingTrash)
        .animation(.default, value: viewModel.currentTab)
        .sheet(item: $viewModel.activeDetail, onDismiss: {
            viewModel.dismissDetail()
        }) { detail in
            switch detail {
            case .similar:
                SimilarComparisonView(viewModel: viewModel)
            case .blurry:
                BlurryReviewView(viewModel: viewModel)
            case .screenshots:
                ScreenshotDocumentView(viewModel: viewModel)
            case .largeFiles:
                LargeFilesView(viewModel: viewModel)
            case .success:
                SuccessSummaryView(viewModel: viewModel)
            }
        }
    }
}


// MARK: - Permission Views
struct PermissionRequestView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(Color("brand-start"))
            Text("欢迎使用智能相册清理")
                .font(.title).bold()
            Text("我们需要访问您的相册以智能分析和管理您的照片。您的数据只会在本地处理，我们绝不会上传您的任何隐私。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Button(action: { viewModel.requestAuthorization() }) {
                Text("授权访问相册")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(height: 55)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color("brand-start"), Color("brand-end")]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
            .shadow(color: Color("brand-start").opacity(0.4), radius: 10, y: 5)

        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)
            Text("无法访问相册")
                .font(.title2).bold()
            Text("请在“设置 > 隐私 > 照片”中允许本应用访问，以便开始清理。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button(action: { UIApplication.shared.open(url) }) {
                    Text("前往设置")
                        .font(.headline)
                }
                .padding(.top)
            }
        }
    }
}


// MARK: - Bottom Navigation Bar
struct BottomNavBar: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        HStack {
            Spacer()
            NavButton(icon: "house.fill", text: "首页", isActive: viewModel.currentTab == .dashboard) {
                viewModel.currentTab = .dashboard
            }
            Spacer()
            NavButton(icon: "photo.stack", text: "相册", isActive: viewModel.currentTab == .album) {
                viewModel.currentTab = .album
            }
            Spacer()
            NavButton(icon: "gearshape.fill", text: "设置", isActive: viewModel.currentTab == .settings) {
                viewModel.currentTab = .settings
            }
            Spacer()
        }
        .frame(height: 85)
        .background(.bar)
        .cornerRadius(24)
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
    }
}

// MARK: - Navigation Button
struct NavButton: View {
    let icon: String
    let text: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isActive ? Color("brand-start") : .gray)
                Text(text)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isActive ? Color("brand-start") : .gray)
            }
        }
    }
}
