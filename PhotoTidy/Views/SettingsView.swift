import SwiftUI
import Photos

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        NavigationStack(path: settingsPathBinding) {
            ZStack {
                blurredBackground
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                        Section {
                            VStack(alignment: .leading, spacing: 20) {
                                proCard
                                dataManagementSection
                                moduleNavigator
                                supportSection
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 48)
                        } header: {
                            header
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 12)
                                .background(.thinMaterial)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .preferences:
                    PreferencesView(viewModel: viewModel)
                case .advanced:
                    AdvancedOperationsView(viewModel: viewModel)
                case .permissions:
                    PermissionsView(viewModel: viewModel)
                }
            }
        }
        .toolbar(viewModel.settingsNavigationPath.isEmpty ? .visible : .hidden, for: .tabBar)
    }
}

private enum SettingsRoute: Hashable {
    case preferences
    case advanced
    case permissions
}

private extension SettingsView {
    var settingsPathBinding: Binding<NavigationPath> {
        Binding(
            get: { viewModel.settingsNavigationPath },
            set: { viewModel.settingsNavigationPath = $0 }
        )
    }
    
    var blurredBackground: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Image("all_album_bg")
                        .resizable()
                        .scaledToFill()
                )
                .clipped()
                .opacity(0.25)
                .blur(radius: 18)
                .ignoresSafeArea()
            
            LinearGradient(
                colors: [
                    Color(UIColor.systemGray6).opacity(0.95),
                    Color(UIColor.systemBackground).opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
    
    var header: some View {
        HStack {
            Spacer()
            Text("设置")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.clear)
            Spacer()
        }
    }
    
    var proCard: some View {
        ZStack {
            LinearGradient(
                colors: [Color("brand-start"), Color("brand-end")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color("brand-start").opacity(0.2), radius: 12, y: 6)
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        Text("PhotoTidy Pro")
                            .font(.system(size: 20, weight: .bold))
                    }
                    Spacer()
                    Text("当前：免费版")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Text("解锁无限清理额度、高级 AI 识别与专属主题。")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))
                
                Button(action: {}) {
                    HStack(spacing: 8) {
                        Text("立即升级")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(SettingsStyle.elevatedButtonBackground)
                    .foregroundColor(Color("brand-start"))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                }
            }
            .padding(20)
        }
    }
    
    var moduleNavigator: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("功能区")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                moduleLink(
                    title: "偏好设置",
                    description: "忽略收藏、删除确认、主题样式",
                    systemImage: "slider.horizontal.3",
                    tint: .blue,
                    route: .preferences
                )
                
                moduleLink(
                    title: "高级操作",
                    description: "清空待删区、重置进度等",
                    systemImage: "wand.and.stars",
                    tint: .orange,
                    route: .advanced
                )
                
                moduleLink(
                    title: "系统权限",
                    description: "照片权限及系统授权管理",
                    systemImage: "lock.shield",
                    tint: .green,
                    route: .permissions
                )
            }
            .background(SettingsStyle.sectionBackground)
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
        }
    }
    
    var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据管理")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                NavigationLink {
                    SkippedPhotosView(viewModel: viewModel)
                } label: {
                    HStack {
                        HStack(spacing: 10) {
                            dataIcon(background: Color.purple.opacity(0.12))
                                .overlay(
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color.purple)
                                )
                            Text("待确认照片")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(viewModel.skippedPhotoRecords.count) 张")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.12))
                                .clipShape(Capsule())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
            .background(SettingsStyle.sectionBackground)
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
        }
    }
    
    var supportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支持与信息")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                supportTile(
                    title: "帮助与反馈",
                    icon: "questionmark.circle",
                    tint: .gray
                ) {}
                Divider().padding(.leading, 56)
                supportTile(
                    title: "联系支持",
                    icon: "bubble.left.and.bubble.right",
                    tint: Color("brand-start")
                ) {}
                Divider().padding(.leading, 56)
                HStack {
                    iconBadge(systemName: "info.circle", color: .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App 版本")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(versionText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(SettingsStyle.sectionBackground)
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
        }
    }
    
    private func moduleLink(
        title: String,
        description: String,
        systemImage: String,
        tint: Color,
        route: SettingsRoute
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                iconBadge(systemName: systemImage, color: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
    
    private func supportTile(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                iconBadge(systemName: icon, color: tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
    
    func iconBadge(systemName: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(color.opacity(0.12))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: systemName)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .semibold))
            )
    }
    
    func dataIcon(background: Color) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(background)
            .frame(width: 36, height: 36)
    }
    
    var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }
}

private enum SettingsStyle {
    static let sectionBackground = Color(UIColor.secondarySystemBackground)
    static let elevatedButtonBackground = Color(UIColor.systemBackground)
}

private struct SettingsToggleTile: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(iconColor.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .font(.system(size: 14, weight: .semibold))
                )
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SettingsToggleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
            Capsule()
                .fill(configuration.isOn ? Color("brand-start") : Color(UIColor.systemGray4))
                .frame(width: 48, height: 26)
            Circle()
                .fill(Color(UIColor.systemBackground))
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .padding(1)
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isOn)
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}

private struct SettingsSubpageHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 42, height: 42)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            
            Spacer()
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

struct PreferencesView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var ignoreFavorites = true
    @State private var confirmDeletion = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsSubpageHeader(title: "偏好设置")
                preferenceToggles
                themeSelector
            }
            .padding(20)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }
    
    private var preferenceToggles: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggleTile(
                icon: "heart",
                iconColor: .pink,
                title: "忽略收藏照片",
                isOn: $ignoreFavorites
            )
            Divider().padding(.leading, 56)
            SettingsToggleTile(
                icon: "bell",
                iconColor: .blue,
                title: "删除确认弹窗",
                isOn: $confirmDeletion
            )
        }
        .background(SettingsStyle.sectionBackground)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
    }
    
    private var themeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "moon.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 15, weight: .semibold))
                    )
                Text("外观主题")
                    .font(.system(size: 13, weight: .semibold))
            }
            
            HStack(spacing: 8) {
                themeButton(theme: .system, label: "跟随系统")
                themeButton(theme: .light, label: "浅色")
                themeButton(theme: .dark, label: "深色")
            }
            .padding(6)
            .background(Color(UIColor.systemGray5))
            .cornerRadius(18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(SettingsStyle.sectionBackground)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
    }
    
    private func themeButton(theme: AppTheme, label: String) -> some View {
        Button(action: { viewModel.selectedTheme = theme }) {
            Text(label)
                .font(.system(size: 12, weight: viewModel.selectedTheme == theme ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(viewModel.selectedTheme == theme ? SettingsStyle.elevatedButtonBackground : Color.clear)
                .foregroundColor(viewModel.selectedTheme == theme ? .primary : .secondary)
                .cornerRadius(14)
                .shadow(color: viewModel.selectedTheme == theme ? Color.black.opacity(0.1) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct AdvancedOperationsView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showingClearPendingAlert = false
    @State private var showingResetProgressAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSubpageHeader(title: "高级操作")
                clearCacheTile
                resetProgressTile
            }
            .padding(20)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .alert("确认清空待删区缓存？", isPresented: $showingClearPendingAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                viewModel.clearPendingDeletionCache()
            }
        } message: {
            Text("这只会移除 App 内暂存的待删除列表，不会影响系统相册。")
        }
        .alert("重置全局清理进度？", isPresented: $showingResetProgressAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                viewModel.resetCleanupProgress()
            }
        } message: {
            Text("将同时清除首页全相册整理与时光机（月度）的进度记录，恢复初始状态。")
        }
    }
    
    private var clearCacheTile: some View {
        HStack(spacing: 10) {
            dataIcon(background: Color.indigo.opacity(0.12))
                .overlay(
                    Image(systemName: "trash.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.indigo)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("清空待删区缓存")
                    .font(.system(size: 13, weight: .semibold))
                Text(pendingCacheDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("清空") {
                showingClearPendingAlert = true
            }
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(canClearPendingCache ? .gray.opacity(0.6) : .red)
            .background(Color(UIColor.systemGray6))
            .clipShape(Capsule())
            .disabled(canClearPendingCache)
        }
        .padding(16)
        .background(SettingsStyle.sectionBackground)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
    }
    
    private var resetProgressTile: some View {
        Button {
            showingResetProgressAlert = true
        } label: {
            HStack(spacing: 10) {
                dataIcon(background: Color.orange.opacity(0.12))
                    .overlay(
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.orange)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("重置清理进度")
                        .font(.system(size: 13, weight: .semibold))
                    Text("全相册与月份记录都会被重置")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(16)
            .background(SettingsStyle.sectionBackground)
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
    
    private var pendingCacheDescription: String {
        let count = viewModel.pendingDeletionItems.count
        if count == 0 {
            return "待删区当前为空"
        }
        return "已暂存 \(count) 张照片"
    }
    
    private var canClearPendingCache: Bool {
        viewModel.pendingDeletionItems.isEmpty
    }
    
    private func dataIcon(background: Color) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(background)
            .frame(width: 36, height: 36)
    }
}

struct PermissionsView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSubpageHeader(title: "系统权限")
                photoPermissionTile
                placeholderTile(title: "通知权限", icon: "bell.badge")
                placeholderTile(title: "相机权限", icon: "camera")
            }
            .padding(20)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }
    
    private var photoPermissionTile: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack {
                iconBadge(systemName: "photo.on.rectangle.angled", color: .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("照片访问权限")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(authorizationStatusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(16)
            .background(SettingsStyle.sectionBackground)
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
    
    private func placeholderTile(title: String, icon: String) -> some View {
        HStack {
            iconBadge(systemName: icon, color: .gray)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text("敬请期待")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary.opacity(0.2))
        }
        .padding(16)
        .background(SettingsStyle.sectionBackground)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, y: 3)
        .opacity(0.8)
    }
    
    private var authorizationStatusText: String {
        switch viewModel.authorizationStatus {
        case .authorized: return "已授权所有照片"
        case .limited: return "仅限部分照片"
        case .denied, .restricted: return "已拒绝"
        case .notDetermined: return "待授权"
        @unknown default: return "未知"
        }
    }
    
    private func iconBadge(systemName: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(color.opacity(0.12))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: systemName)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .semibold))
            )
    }
}
