import SwiftUI
import Photos

struct TimeMachineView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    private var sections: [YearSection] {
        aggregate(from: viewModel.items)
    }

    private var highlightedMonth: MonthSummary? {
        sections
            .flatMap { $0.months }
            .first { $0.pendingCount > 0 } ?? sections.first?.months.first
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
                                VStack(spacing: 20) {
                                    TimeMachineHeader(summary: highlightedMonth)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 24)

                                    LazyVStack(alignment: .leading, spacing: 28, pinnedViews: [.sectionHeaders]) {
                                        ForEach(sections) { section in
                                            Section {
                                                VStack(spacing: 16) {
                                                    ForEach(section.months) { month in
                                                        MonthCard(summary: month, viewModel: viewModel)
                                                    }
                                                }
                                                .padding(.horizontal, 20)
                                            } header: {
                                                StickyYearHeader(year: section.year)
                                                    .padding(.horizontal, 20)
                                                    .padding(.bottom, 6)
                                                    .background(.thinMaterial)
                                                    .id("year-\(section.year)")
                                            }
                                        }
                                    }
                                    .padding(.bottom, 120)
                                }
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

        let grouped = Dictionary(grouping: items) { (item: PhotoItem) -> String in
            let date = item.creationDate ?? Date()
            let comps = Calendar.current.dateComponents([.year, .month], from: date)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)"
        }

        let pendingMap = viewModel.pendingDeletionItems.reduce(into: [String: Int]()) { acc, item in
            let date = item.creationDate ?? Date()
            let comps = Calendar.current.dateComponents([.year, .month], from: date)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            acc[key, default: 0] += 1
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

            return MonthSummary(
                id: key,
                year: year,
                month: month,
                monthTitle: formatterCN.string(from: monthDate),
                englishTitle: formatterEN.string(from: monthDate),
                totalCount: value.count,
                pendingCount: pendingMap[key, default: 0],
                sampleItems: Array(sorted.prefix(2))
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
    let summary: MonthSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("时光机")
                        .font(.system(size: 28, weight: .bold))
                    Text("按月份掌握整理节奏")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
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

            HighlightCard(summary: summary)
        }
    }

    private var headerButtonBackground: Color {
        Color(UIColor.systemBackground)
    }
}

private struct HighlightCard: View {
    let summary: MonthSummary?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("brand-start"), Color("brand-end")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color("brand-start").opacity(0.25), radius: 20, y: 12)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 160, height: 160)
                    .offset(x: 120, y: -80)
            )

            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(summary?.monthTitle ?? "--")
                            .font(.system(size: 34, weight: .bold))
                        Text(summary.map { "\($0.year)" } ?? "--")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .foregroundColor(.white)

                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        Text("本月拍摄 \(summary?.totalCount ?? 0) 张")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

                Spacer()

                Button(action: {}) {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("\(summary?.pendingCount ?? 0)")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.yellow)
                            Text("张")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Text("建议清理")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(22)
        }
        .frame(height: 150)
    }
}

// MARK: - Year & Month Sections

private struct StickyYearHeader: View {
    let year: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(year)")
                .font(.system(size: 22, weight: .bold))
            Text("Year")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MonthCard: View {
    let summary: MonthSummary
    @ObservedObject var viewModel: PhotoCleanupViewModel

    private var hasPending: Bool { summary.pendingCount > 0 }

    var body: some View {
        VStack {
            HStack(spacing: 16) {
                MonthBadge(month: summary.month, englishTitle: summary.englishTitle, highlighted: hasPending)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.monthTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text("拍摄 \(summary.totalCount) 张")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hasPending {
                    ThumbnailStack(items: summary.sampleItems, viewModel: viewModel)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(summary.pendingCount)")
                            .font(.system(size: 16, weight: .bold))
                        Text("待删")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color("brand-start"))
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        Text("已整理")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(hasPending ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

private struct MonthBadge: View {
    let month: Int
    let englishTitle: String
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(String(format: "%02d", month))
                .font(.system(size: 18, weight: .bold))
            Text(englishTitle.uppercased())
                .font(.system(size: 9, weight: .semibold))
        }
        .frame(width: 50, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(highlighted ? Color("brand-start").opacity(0.12) : Color(UIColor.systemGray5))
        )
        .foregroundColor(highlighted ? Color("brand-start") : .secondary)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(highlighted ? Color("brand-start").opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }
}

private struct ThumbnailStack: View {
    let items: [PhotoItem]
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                AssetThumbnailView(
                    asset: item.asset,
                    imageManager: viewModel.imageManager,
                    contentMode: .aspectFill
                )
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
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
    let pendingCount: Int
    let sampleItems: [PhotoItem]
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
