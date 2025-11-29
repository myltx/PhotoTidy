import SwiftUI

/// 首页 Dashboard，按高保真设计稿实现：
/// - 顶部标题 + 存储提示
/// - 中间大卡片「全相册整理」
/// - 下方四个「智能整理」分类入口
struct DashboardView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    var onShowTrash: (() -> Void)? = nil
    @State private var showingResumeResetAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                blurredBackground

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
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
                        } header: {
                            statusBarPlaceholder
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 10)
                                .background(.thinMaterial)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .navigationBarHidden(true)
        }
        .alert("确定重置清理进度？", isPresented: $showingResumeResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                viewModel.resetCleanupProgress()
            }
        } message: {
            Text("清除所有整理进度与选择记录，重新开始全相册整理。")
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
                        .background(cardBackgroundColor)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(cardBackgroundColor, lineWidth: 3))
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
                            .fill(cardBackgroundColor)
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
        Group {
            if let info = viewModel.cleanupResumeInfo {
                resumeHeroCard(info: info)
            } else {
                startHeroCard
            }
        }
    }
    
    private var startHeroCard: some View {
        ZStack(alignment: .bottomLeading) {
            Image("all_album_bg")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

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

                Text("开始全相册整理")
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
                                Text("立即开始")
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
    
    private func resumeHeroCard(info: PhotoCleanupViewModel.CleanupResumeInfo) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image("all_album_bg")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(Color.black.opacity(0.3))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.9),
                    Color.black.opacity(0.4),
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    statusBadge
                    Spacer()
                    pendingBadge(count: info.pendingDeletionCount)
                }

                Text("继续上次进度")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                if let dateText = formattedResumeDate(info.lastStopDate) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .bold))
                        Text("上次停留：\(dateText)")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color("brand-start").opacity(0.9))
                }

                Text(resumeSubtitle(count: info.pendingDeletionCount))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))

                HStack(spacing: 12) {
                    Button {
                        guard !viewModel.isLoading else { return }
                        viewModel.showCleaner(filter: .all)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(viewModel.isLoading ? "准备中…" : "继续")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .foregroundColor(Color("brand-start"))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                    }
                    .disabled(viewModel.isLoading)

                    Button {
                        showingResumeResetAlert = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 44)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
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
                .fill(cardBackgroundColor)
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
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
            Text("进行中")
        }
        .font(.system(size: 11, weight: .bold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.indigo.opacity(0.75))
        .clipShape(Capsule())
    }
    
    private func pendingBadge(count: Int) -> some View {
        Text(count > 0 ? "待删 \(count) 张" : "待删区为空")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .foregroundColor(.white.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private func resumeSubtitle(count: Int) -> String {
        count > 0 ? "待删区中有 \(count) 张照片，记得尽快确认删除" : "等待你的下一次整理"
    }
    
    private func formattedResumeDate(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月d日"
        return formatter.string(from: date)
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

    private var cardBackgroundColor: Color {
        Color(UIColor.systemBackground)
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
                .opacity(0.2)
                .blur(radius: 16)
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

    var statusBarPlaceholder: some View {
        HStack {
            Spacer()
            Text("首页")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.clear)
            Spacer()
        }
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
