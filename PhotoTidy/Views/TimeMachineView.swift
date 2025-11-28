import SwiftUI
import Photos

struct TimeMachineView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var selectedYear: Int?
    @State private var selectedDay: TimelineDay?
    @State private var showingTrash = false

    private let calendar = Calendar.current

    private var allMonths: [TimelineMonth] {
        let formatterCN = DateFormatter()
        formatterCN.locale = Locale(identifier: "zh_CN")
        formatterCN.dateFormat = "M月"

        let formatterEN = DateFormatter()
        formatterEN.locale = Locale(identifier: "en_US")
        formatterEN.dateFormat = "MMMM"

        let grouped = Dictionary(grouping: viewModel.items.compactMap { item -> (DateComponents, PhotoItem)? in
            guard let date = item.creationDate else { return nil }
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            return (comps, item)
        }) { pair in
            DateComponents(year: pair.0.year, month: pair.0.month)
        }

        return grouped.compactMap { entry -> TimelineMonth? in
            let comps = entry.key
            let tuples = entry.value
            guard
                let year = comps.year,
                let month = comps.month,
                let monthDate = calendar.date(from: DateComponents(year: year, month: month)),
                let range = calendar.range(of: .day, in: .month, for: monthDate)
            else {
                return nil
            }

            let photos = tuples.map { $0.1 }
            let dayGroups = Dictionary(grouping: photos, by: { calendar.component(.day, from: $0.creationDate ?? monthDate) })

            let days: [TimelineDay] = range.map { day -> TimelineDay in
                let dayDate = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? monthDate
                let items = dayGroups[day] ?? []
                return TimelineDay(
                    id: "\(year)-\(month)-\(day)",
                    date: dayDate,
                    day: day,
                    items: items.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
                )
            }

            let firstWeekday = calendar.component(.weekday, from: monthDate)
            let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

            return TimelineMonth(
                id: "\(year)-\(month)",
                date: monthDate,
                monthTitle: formatterCN.string(from: monthDate),
                englishTitle: formatterEN.string(from: monthDate),
                leadingEmptyCount: leading,
                days: days
            )
        }
        .sorted { $0.date > $1.date }
    }

    private var filteredMonths: [TimelineMonth] {
        guard let selectedYear else { return allMonths }
        return allMonths.filter { calendar.component(.year, from: $0.date) == selectedYear }
    }

    private var availableYears: [Int] {
        Array(Set(allMonths.map { calendar.component(.year, from: $0.date) })).sorted(by: >)
    }

    private var displayYearText: String {
        if let selectedYear { return "\(selectedYear)年" }
        if let first = filteredMonths.first {
            return "\(calendar.component(.year, from: first.date))年"
        }
        let currentYear = calendar.component(.year, from: Date())
        return "\(currentYear)年"
    }

    private var currentMonthItemCount: Int {
        let now = Date()
        if let current = allMonths.first(where: { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }) {
            return current.totalItemCount
        }
        return allMonths.first?.totalItemCount ?? 0
    }

    var body: some View {
        NavigationStack {
            Group {
                if allMonths.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                            Section {
                                VStack(spacing: 28) {
                                    ForEach(filteredMonths) { month in
                                        MonthCalendarView(
                                            month: month,
                                            onSelectDay: { day in
                                                if !day.items.isEmpty {
                                                    selectedDay = day
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.top, 12)
                            } header: {
                                TimeMachineHeader(
                                    yearText: displayYearText,
                                    years: availableYears,
                                    onSelectYear: { year in
                                        selectedYear = year
                                    },
                                    onResetYear: {
                                        selectedYear = nil
                                    },
                                    monthlyCount: currentMonthItemCount
                                )
                            }
                        }
                    }
                    .background(
                        ZStack {
                            Image("all_album_bg")
                                .resizable()
                                .scaledToFill()
                                .opacity(0.15)
                                .blur(radius: 10)
                                .ignoresSafeArea()
                            Color(UIColor.systemGroupedBackground)
                                .opacity(0.85)
                                .ignoresSafeArea()
                        }
                    )
                    .sheet(item: $selectedDay) { day in
                        TimeMachineDayDetailView(day: day, viewModel: viewModel, onShowTrash: {
                            showingTrash = true
                        })
                            .presentationDetents([.large])
                    }
                    .sheet(isPresented: $showingTrash) {
                        TrashView(viewModel: viewModel)
                            .presentationDetents([.fraction(0.5), .large])
                            .presentationDragIndicator(.visible)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("暂无可展示的时间线")
                .font(.headline)
                .foregroundColor(.primary)
            Text("当你授权访问照片并完成分析后，这里会按照时间展示你的回忆。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 120)
    }
}

private struct TimeMachineHeader: View {
    let yearText: String
    let years: [Int]
    let onSelectYear: (Int) -> Void
    let onResetYear: () -> Void
    let monthlyCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("时光机")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    Button("全部年份") {
                        onResetYear()
                    }
                    ForEach(years, id: \.self) { year in
                        Button("\(year)年") {
                            onSelectYear(year)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(yearText)
                            .font(.system(size: 13, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.systemGray5))
                    .clipShape(Capsule())
                    .foregroundColor(.secondary)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本月待整理")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(monthlyCount)")
                            .font(.system(size: 32, weight: .bold))
                        Text("张")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white)
                }
                Spacer()
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "calendar")
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .semibold))
                    )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .background(
                LinearGradient(
                    colors: [Color("brand-start"), Color("brand-end")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color("brand-start").opacity(0.25), radius: 18, y: 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(.thinMaterial)
    }
}

private struct MonthCalendarView: View {
    let month: TimelineMonth
    var onSelectDay: (TimelineDay) -> Void

    private let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 6), count: 7)
    private let calendar = Calendar.current
    
    private var yearText: String {
        let year = calendar.component(.year, from: month.date)
        return "\(year)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(month.monthTitle)
                    .font(.system(size: 18, weight: .bold))
                Text(month.englishTitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack {
                ForEach(["日","一","二","三","四","五","六"], id: \.self) { weekDay in
                    Text(weekDay)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<month.leadingEmptyCount, id: \.self) { _ in
                    Color.clear.frame(height: 42)
                }

                ForEach(month.days) { day in
                    CalendarDayCell(day: day)
                        .onTapGesture {
                            onSelectDay(day)
                        }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            ZStack(alignment: .topTrailing) {
                Text(yearText)
                    .font(.system(size: 92, weight: .black))
                    .foregroundColor(Color.primary.opacity(0.04))
                    .rotationEffect(.degrees(-6))
                    .padding(.top, -10)
                    .padding(.trailing, -10)
            }
        )
    }
}

private struct CalendarDayCell: View {
    let day: TimelineDay
    private let calendar = Calendar.current

    var body: some View {
        Group {
            if day.items.isEmpty {
                Text("\(day.day)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.35))
                    .frame(height: 42)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            isToday
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color("brand-start"), Color("brand-end")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isToday ? Color.clear : Color("brand-start").opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: isToday ? Color("brand-start").opacity(0.15) : .clear, radius: 6, y: 3)
                    VStack(spacing: 4) {
                        Text("\(day.day)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isToday ? .white : .primary)
                        Circle()
                            .fill(isToday ? Color.white : Color("brand-start"))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 46)
                .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
    }

    private var isToday: Bool {
        calendar.isDate(day.date, inSameDayAs: Date())
    }
}

private struct TimelineMonth: Identifiable {
    let id: String
    let date: Date
    let monthTitle: String
    let englishTitle: String
    let leadingEmptyCount: Int
    let days: [TimelineDay]

    var totalItemCount: Int {
        days.reduce(0) { $0 + $1.items.count }
    }
}

private struct TimelineDay: Identifiable, Hashable {
    let id: String
    let date: Date
    let day: Int
    let items: [PhotoItem]
}

private struct TimeMachineDayDetailView: View {
    let day: TimelineDay
    @ObservedObject var viewModel: PhotoCleanupViewModel
    var onShowTrash: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var previewItem: PhotoItem?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: day.date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(day.items) { item in
                        TimelinePhotoCell(item: item, viewModel: viewModel) {
                            previewItem = item
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("\(dateTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(UIColor.systemBackground))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onShowTrash?()
                        }
                    } label: {
                        Circle()
                            .fill(Color(UIColor.systemGray6))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Image(systemName: "trash")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color("brand-start"))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开待删区")
                }
            }
        }
        .fullScreenCover(item: $previewItem) { item in
            FullScreenPreviewView(item: item, viewModel: viewModel)
        }
    }
}

private struct TimelinePhotoCell: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel
    var onTapPreview: () -> Void

    private var isMarkedForDeletion: Bool {
        viewModel.pendingDeletionItems.contains(where: { $0.id == item.id })
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AssetThumbnailView(
                asset: item.asset,
                imageManager: viewModel.imageManager,
                contentMode: .aspectFill
            )
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {
                onTapPreview()
            }

            Button {
                viewModel.setDeletion(item, to: !isMarkedForDeletion)
            } label: {
                Image(systemName: isMarkedForDeletion ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isMarkedForDeletion ? Color("brand-start") : .white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
            .padding(8)
        }
    }
}
