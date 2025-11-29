import SwiftUI
import Photos

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var ignoreFavorites = true
    @State private var confirmDeletion = true
    @State private var showingClearPendingAlert = false
    @State private var showingResetProgressAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                blurredBackground

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                        Section {
                            VStack(alignment: .leading, spacing: 24) {
                                proCard
                                dataManagementSection
                                cleanupSection
                                generalSection
                                footerSection
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 60)
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
        }
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
}

private extension SettingsView {
    var blurredBackground: some View {
        ZStack {
            // By using an overlay on a Rectangle, we prevent the image's oversized frame
            // from influencing the ZStack's layout, which was causing the width issue.
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
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color("brand-start").opacity(0.25), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        Text("PhotoTidy Pro")
                            .font(.system(size: 20, weight: .bold))
                    }
                    Spacer()
                    Text("当前：免费版")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }

                Text("解锁无限清理额度、高级 AI 识别与专属主题。")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.9))

                Button(action: {}) {
                    HStack(spacing: 8) {
                        Text("立即升级")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(elevatedButtonBackground)
                    .foregroundColor(Color("brand-start"))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                }
            }
            .padding(24)
        }
    }

    var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("清理偏好")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
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
            .background(sectionBackground)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }

    var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通用")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                themeTile
                Divider().padding(.leading, 56)
                permissionTile
                Divider().padding(.leading, 56)
                helpTile
            }
            .background(sectionBackground)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }

    var themeTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                iconBadge(systemName: "moon.fill", color: .purple)
                Text("外观主题")
                    .font(.system(size: 14, weight: .semibold))
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
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    var permissionTile: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack {
                iconBadge(systemName: "photo.on.rectangle.angled", color: .green)
                Text("照片访问权限")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text(authorizationStatusText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }

    var helpTile: some View {
        Button(action: {}) {
            HStack {
                iconBadge(systemName: "questionmark.circle", color: .gray)
                Text("帮助与反馈")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }

    var footerSection: some View {
        VStack(spacing: 6) {
            Text("Version 1.0.0 (Build 1024)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button(action: {}) {
                Text("联系支持")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color("brand-start").opacity(0.12))
                    .foregroundColor(Color("brand-start"))
                    .cornerRadius(14)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
    
    var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据管理")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                NavigationLink {
                    SkippedPhotosView(viewModel: viewModel)
                } label: {
                    HStack {
                        HStack(spacing: 12) {
                            dataIcon(background: Color.purple.opacity(0.12))
                                .overlay(
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color.purple)
                                )
                            Text("待确认照片")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(viewModel.skippedPhotoRecords.count) 张")
                                .font(.system(size: 10, weight: .bold))
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
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.plain)
                
                Divider().padding(.leading, 56)
                
                HStack(spacing: 12) {
                    dataIcon(background: Color.indigo.opacity(0.12))
                        .overlay(
                            Image(systemName: "trash.slash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.indigo)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("清空待删区缓存")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(pendingCacheDescription)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                    Spacer()
                    Button("清空") {
                        showingClearPendingAlert = true
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundColor(canClearPendingCache ? .gray.opacity(0.6) : Color.red)
                    .background(Color(UIColor.systemGray6))
                    .clipShape(Capsule())
                    .disabled(canClearPendingCache)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                
                Divider().padding(.leading, 56)
                
                Button {
                    showingResetProgressAlert = true
                } label: {
                    HStack(spacing: 12) {
                        dataIcon(background: Color.orange.opacity(0.12))
                            .overlay(
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color.orange)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("重置清理进度")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("全相册与月份记录都会被重置")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.plain)
            }
            .background(sectionBackground)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }

    func iconBadge(systemName: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.opacity(0.12))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: systemName)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .semibold))
            )
    }

    func themeButton(theme: AppTheme, label: String) -> some View {
        Button(action: { viewModel.selectedTheme = theme }) {
            Text(label)
                .font(.system(size: 12, weight: viewModel.selectedTheme == theme ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(viewModel.selectedTheme == theme ? elevatedButtonBackground : Color.clear)
                .foregroundColor(viewModel.selectedTheme == theme ? .primary : .secondary)
                .cornerRadius(14)
                .shadow(color: viewModel.selectedTheme == theme ? Color.black.opacity(0.1) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var authorizationStatusText: String {
        switch viewModel.authorizationStatus {
        case .authorized: return "所有照片"
        case .limited: return "部分照片"
        case .denied, .restricted: return "已拒绝"
        case .notDetermined: return "待授权"
        @unknown default: return "未知"
        }
    }

    var sectionBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }

    var elevatedButtonBackground: Color {
        Color(UIColor.systemBackground)
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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(background)
            .frame(width: 40, height: 40)
    }
}

private struct SettingsToggleTile: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconColor.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .font(.system(size: 14, weight: .semibold))
                )
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SettingsToggleStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
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
