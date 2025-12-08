import SwiftUI

struct ContentView: View {
    @StateObject private var cleanupViewModel = PhotoCleanupViewModel()
    @State private var selection: AppTab = .dashboard
    @State private var showingTrash = false

    var body: some View {
        TabView(selection: $selection) {
            DashboardContainerView(viewModel: cleanupViewModel, showingTrash: $showingTrash)
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(AppTab.dashboard)

            TimelineView()
                .tabItem {
                    Label("时光机", systemImage: "clock.arrow.circlepath")
                }
                .tag(AppTab.timeline)

            SettingsView(viewModel: cleanupViewModel)
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .tint(Color("brand-start"))
        .sheet(isPresented: $showingTrash) {
            NavigationStack {
                TrashView(viewModel: cleanupViewModel)
            }
        }
        .fullScreenCover(isPresented: $cleanupViewModel.isShowingCleaner) {
            NavigationStack {
                CarouselReviewView(cleanupViewModel: cleanupViewModel)
                    .navigationTitle("全相册整理")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                cleanupViewModel.dismissCleaner()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .padding(8)
                                    .background(Color(UIColor.systemBackground))
                                    .clipShape(Circle())
                            }
                        }
                    }
            }
            .ignoresSafeArea()
        }
    }
}

private enum AppTab: Hashable {
    case dashboard
    case timeline
    case settings
}

private struct DashboardContainerView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Binding var showingTrash: Bool

    var body: some View {
        DashboardView(viewModel: viewModel, onShowTrash: {
            showingTrash = true
        })
    }
}
