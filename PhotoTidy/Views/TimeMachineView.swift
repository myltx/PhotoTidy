import SwiftUI

struct TimeMachineView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @StateObject private var timelineViewModel: TimeMachineTimelineViewModel
    @State private var showingResetAlert = false

    init(viewModel: PhotoCleanupViewModel) {
        self.viewModel = viewModel
        _timelineViewModel = StateObject(wrappedValue: TimeMachineTimelineViewModel(dataSource: viewModel))
    }

    private let squareColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGray5)
                    .opacity(0.35)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    Divider()
                        .overlay(Color.gray.opacity(0.15))
                    content
                }
            }
            .navigationBarHidden(true)
        }
        .alert("重置时光机进度？", isPresented: $showingResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                viewModel.resetTimeMachineProgress()
            }
        } message: {
            Text("将清除待删与已确认记录，重新开始按月份整理。")
        }
    }

    private var content: some View {
        Group {
            if timelineViewModel.sections.isEmpty {
                EmptyTimelineView()
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(timelineViewModel.sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                MonthGridHeader(
                                    title: "\(section.year) 年",
                                    primary: section.year == timelineViewModel.sections.first?.year
                                )
                                MonthGridView(section: section, columns: squareColumns) { info in
                                    viewModel.showCleaner(forMonth: info.year, month: info.month)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .padding(.top, 12)
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
                .background(Color(UIColor.systemGray6).opacity(0.65))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("时光机")
                        .font(.system(size: 28, weight: .bold))
                    Text("以月份查看待理 / 进行 / 完成状态")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if FeatureToggles.showCleanupResetControls {
                    Button {
                        showingResetAlert = true
                    } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 16) {
                YearBadge(text: heroYearLabel)
                LegendView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

private extension TimeMachineView {
    var heroYearLabel: String {
        if let year = timelineViewModel.sections.first?.year {
            return "\(year) 年"
        }
        return "年份"
    }
}

private struct MonthGridHeader: View {
    let title: String
    var primary: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.title3.bold())
            if primary {
                Text("当前年份")
                    .font(.caption.bold())
                    .foregroundColor(.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.08))
                    .clipShape(Capsule())
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

private struct MonthGridView: View {
    let section: TimeMachineTimelineViewModel.YearSection
    let columns: [GridItem]
    var onSelect: (MonthInfo) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(section.months) { info in
                MonthSquare(info: info) {
                    onSelect(info)
                }
            }
        }
    }
}

private struct MonthSquare: View {
    let info: MonthInfo
    var onTap: () -> Void

    private struct Palette {
        let border: Color
        let background: Color
        let text: Color
        let glow: Color
    }

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.border, lineWidth: 1.5)
                )
                .overlay(
                    Text(monthLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.text)
                )
                .frame(height: 48)
        }
        .buttonStyle(.plain)
    }

    private var monthLabel: String {
        "\(info.month)"
    }

    private var palette: Palette {
        switch displayStatus {
        case .notStarted:
            return Palette(
                border: Color.indigo.opacity(0.85),
                background: Color.white,
                text: Color.indigo,
                glow: Color.indigo.opacity(0.12)
            )
        case .inProgress:
            return Palette(
                border: Color.orange.opacity(0.9),
                background: Color.white,
                text: Color.orange,
                glow: Color.orange.opacity(0.15)
            )
        case .completed:
            return Palette(
                border: Color.green.opacity(0.45),
                background: Color.green.opacity(0.12),
                text: Color.green,
                glow: Color.green.opacity(0.08)
            )
        }
    }

    private var displayStatus: CleaningStatus {
        if info.totalPhotos == 0 && info.processedCount == 0 {
            return .completed
        }
        return info.status
    }
}

private struct YearBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.bold())
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.gray.opacity(0.12))
        )
    }
}

private struct LegendView: View {
    var body: some View {
        HStack(spacing: 12) {
            LegendItem(color: Color.indigo, text: "待理")
            LegendItem(color: Color.orange, text: "进行")
            LegendItem(color: Color.green, text: "完成")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.gray.opacity(0.1))
        )
    }
}

private struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption2.weight(.bold))
            
                .foregroundColor(.secondary)
        }
    }
}

private struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.questionmark")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text("暂无可展示的月份")
                .font(.headline)
            Text("完成一次整理或开放照片权限后，这里会按月份呈现状态。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
        )
    }
}
