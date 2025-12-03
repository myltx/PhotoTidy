import SwiftUI
import UIKit

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
        .alert("清除全相册整理进度？", isPresented: $showingResumeResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                viewModel.resetSmartCleanupProgressOnly()
            }
        } message: {
            Text("仅重置首页全相册整理进度，时光机（月度）记录不受影响。")
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
            if let info = viewModel.smartCleanupResumeInfo {
                resumeHeroCard(info: info)
            } else {
                startHeroCard
            }
        }
    }
    
    private var startHeroCard: some View {
        SmartCleanupStartCard(viewModel: viewModel)
    }
    
    private func resumeHeroCard(info: PhotoCleanupViewModel.SmartCleanupResumeInfo) -> some View {
        SmartCleanupHeroCard(
            viewModel: viewModel,
            info: info,
            isLoading: viewModel.isLoading,
            showReset: FeatureToggles.showCleanupResetControls,
            onReset: { showingResumeResetAlert = true }
        )
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
                iconColor: .indigo,
                action: { viewModel.showDetail(.similar) },
                onAppear: { viewModel.preloadSampleThumbnails(for: .similar, target: .dashboardCard) }
            )

            SmartTile(
                title: "模糊照片",
                systemIcon: "drop.triangle",
                iconColor: .orange,
                action: { viewModel.showDetail(.blurry) },
                onAppear: { viewModel.preloadSampleThumbnails(for: .blurred, target: .dashboardCard) }
            )

            SmartTile(
                title: "截图文档",
                systemIcon: "doc.richtext",
                iconColor: .blue,
                action: { viewModel.showDetail(.screenshots) },
                onAppear: { viewModel.preloadSampleThumbnails(for: .screenshots, target: .dashboardCard) }
            )

            SmartTile(
                title: "大文件",
                systemIcon: "film",
                iconColor: .green,
                action: { viewModel.showDetail(.largeFiles) },
                onAppear: { viewModel.preloadSampleThumbnails(for: .large, target: .tinderCard) }
            )
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
    var onAppear: (() -> Void)? = nil
    @State private var hasAppeared = false

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
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            onAppear?()
        }
    }
}

private struct SmartCleanupHeroCard: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    let info: PhotoCleanupViewModel.SmartCleanupResumeInfo
    let isLoading: Bool
    let showReset: Bool
    let onReset: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("all_album_bg")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(Color.black.opacity(0.35))

            LinearGradient(
                colors: [Color("brand-start").opacity(0.85), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    AnimatedStatusBadge(label: "进行中")
                    Spacer()
                    PendingBadge(count: info.pendingDeletionCount, icon: "trash")
                }

                Text("继续整理")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(-0.5)

                if let dateText = formattedResumeDate(info.anchorPhoto?.creationDate) {
                    Label("上次停留：\(dateText)", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color("brand-start").opacity(0.9))
                }

                Text(resumeSubtitle(count: info.pendingDeletionCount))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))

                HStack(spacing: 12) {
                    Button {
                        guard !isLoading else { return }
                        viewModel.resumeSmartCleanup()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isLoading ? "hourglass" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color("brand-start"))
                            Text(isLoading ? "准备中…" : "继续")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
                    }
                    .disabled(isLoading)

                    if showReset {
                        Button(action: onReset) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 48, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 22, y: 14)
        .onTapGesture {
            guard !isLoading else { return }
            viewModel.showCleaner(filter: .all)
        }
    }

    private func resumeSubtitle(count: Int) -> String {
        count > 0 ? "待删区中有 \(count) 张，记得尽快确认删除" : "等待你的下一次整理"
    }

    private func formattedResumeDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月d日"
        return formatter.string(from: date)
    }
}

private struct SmartCleanupStartCard: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("all_album_bg")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(Color.black.opacity(0.35))

            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("推荐")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.9))
                    .foregroundColor(.white)
                    .clipShape(Capsule())

                Text("全相册整理")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                Text("左滑删除，右滑保留")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))

                Button {
                    guard !viewModel.isLoading else { return }
                    viewModel.showCleaner(filter: .all)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isLoading ? "hourglass" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.indigo)
                        Text(viewModel.isLoading ? "准备中…" : "开始")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                }
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 12)
        .onTapGesture {
            guard !viewModel.isLoading else { return }
            viewModel.showCleaner(filter: .all)
        }
    }
}

private struct PendingBadge: View {
    let count: Int
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.indigo.opacity(0.9))
            Text(count > 0 ? "待删 \(count) 张" : "待删区为空")
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct AnimatedStatusBadge: View {
    let label: String
    @State private var animate = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 12, height: 12)
                    .scaleEffect(animate ? 1.6 : 0.6)
                    .opacity(animate ? 0 : 1)
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.indigo.opacity(0.9))
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}
