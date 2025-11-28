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
        }
    }
}

// MARK: - Sections
private extension DashboardView {
    var headerSection: some View {
        VStack(spacing: 18) {
            HStack {
                HStack(spacing: 12) {
                    Image("duck")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(greetingText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("PhotoTidy")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                Button {
                    onShowTrash?()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 46, height: 46)
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color("brand-start"))
                    }
                    .overlay(alignment: .topTrailing) {
                        if viewModel.pendingDeletionItems.count > 0 {
                            Text("\(min(viewModel.pendingDeletionItems.count, 99))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开待删区")
            }

            storageSummaryCard
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
    
    private var storageSummaryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    Text("存储空间")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(usagePercentageText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color("brand-start"))
                }
                
                storageProgressBar
                
                VStack(alignment: .leading, spacing: 4) {
                    if let detail = storageUsageDetailText {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text(storageSuggestionText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color("brand-start"))
                }
                
                if let status = analysisStatusText {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.5)
                        Text(status)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            ZStack {
                Circle()
                    .fill(Color(UIColor.systemGray6))
                    .frame(width: 52, height: 52)
                Image(systemName: "internaldrive")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }
    
    private var storageProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(UIColor.systemGray5))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color("brand-start"), Color("brand-end")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(CGFloat(usageProgress) * proxy.size.width, 8))
            }
        }
        .frame(height: 10)
    }
    
    private var usagePercentageText: String {
        if let percent = viewModel.deviceStorageUsage.formattedPercentageText {
            return "已用 \(percent)"
        }
        return "正在计算…"
    }
    
    private var storageUsageDetailText: String? {
        viewModel.deviceStorageUsage.formattedUsageDetailText
    }
    
    private var usageProgress: Double {
        min(max(viewModel.deviceStorageUsage.usagePercentage, 0), 1)
    }
    
    private var storageSuggestionText: String {
        let bytes = viewModel.pendingDeletionTotalSize
        if bytes > 0 {
            return "建议清理 \(bytes.fileSizeDescription)"
        }
        return "定期清理可保持充足空间"
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }
    
    private var analysisStatusText: String? {
        if viewModel.isLoading {
            return "正在加载相册…"
        } else if viewModel.isAnalyzing {
            return "AI 正在分析中…"
        }
        return nil
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
