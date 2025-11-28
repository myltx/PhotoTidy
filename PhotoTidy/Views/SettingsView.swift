import SwiftUI
import Photos

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    proCard
                    cleanupPreferences
                    generalSection
                    helperSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .background(Color.clear)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "person.crop.circle")
                            .imageScale(.large)
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }
}

private extension SettingsView {
    private var authorizationStatusText: String {
        switch viewModel.authorizationStatus {
        case .authorized:
            return "所有照片"
        case .limited:
            return "部分照片"
        case .denied, .restricted:
            return "已拒绝"
        case .notDetermined:
            return "待授权"
        @unknown default:
            return "未知"
        }
    }

    var proCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Smart Cleaner Pro", systemImage: "crown.fill")
                    .foregroundColor(.yellow)
                    .font(.headline)
                Spacer()
                Text("Free")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            }
            Text("解锁无限制清理和高级 AI 识别").font(.subheadline).foregroundColor(.white.opacity(0.8))
            Button("升级方案") {}.font(.headline).frame(maxWidth: .infinity).padding().background(Color.white).foregroundColor(Color("brand-start")).cornerRadius(14)
        }
        .padding()
        .background(LinearGradient(colors: [Color("brand-start"), Color("brand-end")], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(28)
        .shadow(color: Color("brand-start").opacity(0.3), radius: 18, y: 8)
    }

    var cleanupPreferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("清理偏好").font(.caption).foregroundColor(.secondary).padding(.leading, 8)
            VStack(spacing: 0) {
                toggleRow(icon: "heart.slash", title: "忽略收藏照片", enabled: true)
                Divider()
                toggleRow(icon: "bell", title: "删除确认弹窗", enabled: true)
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(22)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    func toggleRow(icon: String, title: String, enabled: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: .constant(enabled))
                .labelsHidden()
        }
        .padding()
    }

    var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("主题与通用").font(.caption).foregroundColor(.secondary).padding(.leading, 8)
            VStack(spacing: 0) {
                themeSelectorRow
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                Divider()
                permissionStatusRow
                    .padding()
                Divider()
                settingRow(icon: "questionmark.circle", title: "帮助与反馈", detail: nil, showChevron: true)
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(22)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    var themeSelectorRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("主题外观", systemImage: "moon")
                .foregroundColor(.primary)
                .font(.headline)
                .padding(.bottom, 4)

            Picker("", selection: $viewModel.selectedTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var permissionStatusRow: some View {
        Button(action: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack {
                Label("照片访问权限", systemImage: "photo.on.rectangle.angled")
                    .foregroundColor(.primary)
                Spacer()
                Text(authorizationStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    func settingRow(icon: String, title: String, detail: String?, showChevron: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(.primary)
            Spacer()
            if let detail = detail {
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            if showChevron {
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
    }

    var helperSection: some View {
        VStack(spacing: 6) {
            Text("Version 1.0.0").font(.caption).foregroundColor(.secondary)
            Button("联系支持") {}
                .font(.subheadline).bold()
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color(UIColor.systemBackground))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
        }
        .frame(maxWidth: .infinity)
    }
}
