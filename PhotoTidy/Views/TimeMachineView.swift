import SwiftUI
import Photos

struct TimeMachineView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showingResetAlert = false

    private var sections: [YearSection] {
        aggregate(from: viewModel.items)
    }

    private var highlightedMonth: MonthSummary? {
        sections
            .flatMap { $0.months }
            .first { $0.status.needsAttention || $0.isCurrentMonth } ?? sections.first?.months.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if sections.isEmpty {
                                EmptyTimelineView()
                                    .padding(.top, 80)
                                    .padding(.horizontal, 24)
                            } else {
                                VStack(spacing: 28) {
                                    TimeMachineHeader(onReset: {
                                        showingResetAlert = true
                                    })
                                        .padding(.horizontal, 20)
                                        .padding(.top, 24)

                                    ForEach(sections) { section in
                                        YearGroupView(
                                            section: section,
                                            featuredMonthID: highlightedMonth?.id,
                                            onSelectMonth: { summary in
                                                viewModel.showCleaner(forMonth: summary.year, month: summary.month)
                                            }
                                        )
                                        .padding(.horizontal, 20)
                                    }

                                }
                                .padding(.bottom, 60)
                            }
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
        .alert("重置时光机进度？", isPresented: $showingResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                viewModel.resetTimeMachineProgress()
            }
        } message: {
            Text("将清除所有月份的整理进度与选择记录，重新开始按月份整理。")
        }
    }
}

private extension TimeMachineView {
    var background: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Image("all_album_bg")
                        .resizable()
                        .scaledToFill()
                )
                .clipped()
                .opacity(0.18)
                .blur(radius: 16)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(UIColor.systemGray6).opacity(0.95),
                    Color(UIColor.systemBackground).opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    func aggregate(from items: [PhotoItem]) -> [YearSection] {
        guard !items.isEmpty else { return [] }

        let formatterCN = DateFormatter()
        formatterCN.locale = .init(identifier: "zh_CN")
        formatterCN.dateFormat = "M月"

        let formatterEN = DateFormatter()
        formatterEN.locale = .init(identifier: "en_US")
        formatterEN.dateFormat = "MMM"

        let progressFormatter = DateFormatter()
        progressFormatter.locale = .init(identifier: "zh_CN")
        progressFormatter.dateFormat = "M月d日"

        let grouped = Dictionary(grouping: items) { (item: PhotoItem) -> String in
            let date = item.creationDate ?? Date()
            let comps = Calendar.current.dateComponents([.year, .month], from: date)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)"
        }

        let summaries = grouped.compactMap { (key, value) -> MonthSummary? in
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]),
                  year > 0, month > 0
            else { return nil }

            let monthDate = Calendar.current.date(from: DateComponents(year: year, month: month)) ?? Date()
            let sorted = value.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }

            let status = viewModel.monthStatuses[key] ?? viewModel.computeMonthStatus(photos: value)
            let isCurrentMonth = Calendar.current.isDate(monthDate, equalTo: Date(), toGranularity: .month)
            let progress = viewModel.timeMachineProgress(year: year, month: month)
            let processedCount = progress?.processedCount ?? 0
            var progressDescription: String?
            if processedCount > 0, !sorted.isEmpty {
                let cappedCount = min(processedCount, sorted.count)
                let clampedIndex = min(max(cappedCount - 1, 0), sorted.count - 1)
                if clampedIndex < sorted.count {
                    let date = sorted[clampedIndex].creationDate ?? monthDate
                    let dateText = progressFormatter.string(from: date)
                    progressDescription = "上次停留：\(dateText) · 已整理 \(cappedCount)/\(sorted.count) 张"
                }
            }

            return MonthSummary(
                id: key,
                year: year,
                month: month,
                monthTitle: formatterCN.string(from: monthDate),
                englishTitle: formatterEN.string(from: monthDate),
                totalCount: status.totalPhotos,
                status: status,
                isCurrentMonth: isCurrentMonth,
                sampleItems: Array(sorted.prefix(2)),
                processedCount: processedCount,
                progressDescription: progressDescription
            )
        }
        .sorted { lhs, rhs in
            lhs.year == rhs.year ? lhs.month > rhs.month : lhs.year > rhs.year
        }

        let groupedByYear = Dictionary(grouping: summaries) { $0.year }
        return groupedByYear.map { (year, months) in
            YearSection(year: year, months: months.sorted { $0.month > $1.month })
        }
        .sorted { $0.year > $1.year }
    }
}

// MARK: - Header & Highlight

private struct TimeMachineHeader: View {
    var onReset: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("时光机")
                    .font(.system(size: 28, weight: .bold))
                Text("按月份掌握整理节奏")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: onReset) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise.circle")
                        Text("重置进度")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.systemGray5))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    HStack(spacing: 6) {
                        Text("全部时间")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(headerButtonBackground)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var headerButtonBackground: Color {
        Color(UIColor.systemBackground)
    }
}

// MARK: - Year & Month Sections

private struct YearGroupView: View {
    let section: YearSection
    let featuredMonthID: String?
    let onSelectMonth: (MonthSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(section.year)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            VStack(spacing: 16) {
                ForEach(section.months) { month in
                    MonthCard(
                        summary: month,
                        isFeatured: month.id == featuredMonthID,
                        onTap: { onSelectMonth(month) }
                    )
                }
            }
        }
    }
}

private struct MonthCard: View {
    let summary: MonthSummary
    let isFeatured: Bool
    var onTap: (() -> Void)?

    var body: some View {
        Group {
            if isFeatured {
                FeaturedMonthCard(summary: summary)
            } else {
                StandardMonthCard(summary: summary)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onTapGesture {
            guard canTriggerAction else { return }
            onTap?()
        }
        .opacity(canTriggerAction ? 1 : 0.8)
    }

    private var canTriggerAction: Bool {
        !summary.status.userCleaned || summary.isCurrentMonth
    }
}

private struct MonthBadge: View {
    let month: Int
    let englishTitle: String
    let highlighted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(highlighted ? Color("brand-start").opacity(0.18) : Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(highlighted ? 0.15 : 0.08), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
            VStack(spacing: 3) {
                Text(String(format: "%02d", month))
                    .font(.system(size: 18, weight: .bold))
                Text(englishTitle.uppercased())
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(highlighted ? Color("brand-start") : .primary)
        }
        .frame(width: 52, height: 56)
    }
}

private struct FeaturedMonthCard: View {
    let summary: MonthSummary

    private var status: MonthStatus { summary.status }

    private var metrics: [TimelineMetric] {
        if status.userCleaned {
            return [TimelineMetric(color: Color.green.opacity(0.85), ratio: 1)]
        }

        let total = max(Double(status.totalPhotos), 1)
        let pending = min(Double(status.predictedPendingCount), total)
        let remaining = max(total - pending, 0)
        let review = remaining * 0.4
        let good = max(remaining - review, 0)

        let computed = [
            TimelineMetric(color: Color.yellow.opacity(0.9), ratio: pending / total),
            TimelineMetric(color: Color.green.opacity(0.8), ratio: review / total),
            TimelineMetric(color: Color.white.opacity(0.35), ratio: good / total)
        ].filter { $0.ratio > 0 }

        if computed.isEmpty {
            return [TimelineMetric(color: Color.white.opacity(0.2), ratio: 1)]
        }
        return computed
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("brand-start"), Color("brand-end")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color("brand-start").opacity(0.25), radius: 24, y: 12)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 180, height: 180)
                    .offset(x: 110, y: -90)
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(summary.monthTitle)
                                .font(.system(size: 32, weight: .bold))
                            if summary.isCurrentMonth {
                                Text("Current")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(.white)

                        Text("本月拍摄 \(summary.totalCount) 张")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                        
                        if let progressText = summary.progressDescription {
                            Text(progressText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.85))
                                .padding(.top, 2)
                        }
                    }

                    Spacer()

                    if status.userCleaned {
                        HStack(spacing: 6) {
                            Text("已清理")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("\(status.predictedPendingCount)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text("待清理")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            Text("查看详情")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                }

                MultiSegmentProgressBar(segments: metrics)
                    .frame(height: 6)

                HStack {
                    Text(status.userCleaned ? "整理完成" : "相似 / 截图 / 模糊")
                    Spacer()
                    Text(status.userCleaned ? "等待新照片" : "良好照片")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            }
            .padding(22)
        }
    }
}

private struct StandardMonthCard: View {
    let summary: MonthSummary

    private var status: MonthStatus { summary.status }

    private var shouldShowPending: Bool {
        !status.userCleaned && (status.predictedPendingCount > 0 || summary.isCurrentMonth)
    }

    var body: some View {
        HStack(spacing: 16) {
            MonthBadge(
                month: summary.month,
                englishTitle: summary.englishTitle,
                highlighted: shouldShowPending
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.monthTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Text("拍摄 \(summary.totalCount) 张")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if let progressText = summary.progressDescription {
                    Text(progressText)
                        .font(.system(size: 11))
                        .foregroundColor(Color("brand-start"))
                }
            }

            Spacer()

            if shouldShowPending {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(status.predictedPendingCount)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    Text("待处理")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color("brand-start"))
                }
                .padding(.trailing, 4)
            } else if status.userCleaned {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("已清理")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color("brand-start"))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "hand.thumbsup")
                        .font(.system(size: 12, weight: .bold))
                    Text("状态良好")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemGray5))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct TimelineMetric: Identifiable {
    let id = UUID()
    let color: Color
    let ratio: Double
}

private struct MultiSegmentProgressBar: View {
    let segments: [TimelineMetric]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(segment.color)
                        .frame(width: max(CGFloat(segment.ratio) * proxy.size.width, 4))
                }
            }
        }
    }
}

// MARK: - Models & Empty State

private struct MonthSummary: Identifiable {
    let id: String
    let year: Int
    let month: Int
    let monthTitle: String
    let englishTitle: String
    let totalCount: Int
    let status: MonthStatus
    let isCurrentMonth: Bool
    let sampleItems: [PhotoItem]
    let processedCount: Int
    let progressDescription: String?
}

private struct YearSection: Identifiable {
    let year: Int
    let months: [MonthSummary]

    var id: Int { year }
}

private struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text("暂无可展示的时间线")
                .font(.headline)
            Text("当您完成一次整理或开放照片权限后，这里会按月份呈现精彩回忆。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

private extension TimeMachineView {
    var statusBarPlaceholder: some View {
        HStack {
            Spacer()
            Text("时光机")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.clear)
            Spacer()
        }
    }
}
