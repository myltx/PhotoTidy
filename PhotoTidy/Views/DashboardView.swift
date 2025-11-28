import SwiftUI

/// 首页 Dashboard，按高保真设计稿实现：
/// - 顶部标题 + 存储提示
/// - 中间大卡片「全相册整理」
/// - 下方四个「智能整理」分类入口
struct DashboardView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    var onShowTrash: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    heroCleanerCard
                    smartCleanupTitle
                    smartCleanupGrid
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onShowTrash?()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "trash")
                                .imageScale(.medium)
                            if viewModel.pendingDeletionItems.count > 0 {
                                Text("\(min(viewModel.pendingDeletionItems.count, 99))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color("brand-start"))
                                    .clipShape(Capsule())
                                    .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .accessibilityLabel("打开待删区")
                }
            }
        }
    }
}

// MARK: - Sections
private extension DashboardView {
    var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("存储概览")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(storageUsageDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let detailText = storageUsageDetailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if viewModel.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                        Text("正在加载相册…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                } else if viewModel.isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                        Text("AI 正在分析相似照片…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
            Image("duck")
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .background(Color(UIColor.systemBackground))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }

    var heroCleanerCard: some View {
        ZStack(alignment: .bottomLeading) {
            // 背景图：改为使用本地 Assets，避免依赖网络
            Image("all_album_bg")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // 底部向上的渐变遮罩，增强文字可读性
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("推荐")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.9))
                    .foregroundColor(.white)
                    .clipShape(Capsule())

                Text("全相册整理")
                    .font(.title2).bold()
                    .foregroundColor(.white)

                Text("左滑删除，右滑保留")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.8))

                Button(action: {
                    guard !viewModel.isLoading else { return }
                    viewModel.showCleaner(filter: .all)
                }) {
                    Group {
                        if viewModel.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("正在准备…")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.secondary)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color("brand-start"))
                                Text("开始")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemBackground).opacity(viewModel.isLoading ? 0.8 : 1))
                    .cornerRadius(14)
                }
                .padding(.top, 6)
                .disabled(viewModel.isLoading)
            }
            .padding(.leading, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
        .onTapGesture {
            guard !viewModel.isLoading else { return }
            viewModel.showCleaner(filter: .all)
        }
    }

    var smartCleanupTitle: some View {
        Text("智能整理")
            .font(.subheadline).bold()
            .foregroundColor(.primary)
    }

    var smartCleanupGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            SmartTile(
                title: "相似照片",
                systemIcon: "rectangle.stack",
                iconColor: .indigo
            ) {
                viewModel.showDetail(.similar)
            }

            SmartTile(
                title: "模糊照片",
                systemIcon: "drop.triangle",
                iconColor: .orange
            ) {
                viewModel.showDetail(.blurry)
            }

            SmartTile(
                title: "截图文档",
                systemIcon: "doc.richtext",
                iconColor: .blue
            ) {
                viewModel.showDetail(.screenshots)
            }

            SmartTile(
                title: "大文件",
                systemIcon: "film",
                iconColor: .green
            ) {
                viewModel.showDetail(.largeFiles)
            }
        }
        .padding(.bottom, 40)
    }
    
    var storageUsageDescription: String {
        if let percent = viewModel.deviceStorageUsage.formattedPercentageText {
            return "本机存储已用 \(percent)"
        } else {
            return "正在获取本机存储…"
        }
    }
    
    var storageUsageDetailText: String? {
        viewModel.deviceStorageUsage.formattedUsageDetailText
    }
}

// MARK: - Smart Tile
private struct SmartTile: View {
    let title: String
    let systemIcon: String
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
                    .padding(.bottom, 4)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(UIColor.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
