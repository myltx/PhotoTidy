import SwiftUI
import UIKit

struct TimeMachineView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showingResetAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.timeMachineSections.isEmpty {
                    ScrollView {
                        EmptyTimelineView()
                            .padding(.horizontal, 24)
                            .padding(.top, 60)
                    }
                    .background(Color(UIColor.systemGray6).opacity(0.65))
                } else {
                    List {
                        ForEach(viewModel.timeMachineSections) { section in
                            Section(header: Text("\(section.year) 年")) {
                                ForEach(section.months) { month in
                                    Button {
                                        viewModel.showCleaner(forMonth: month.year, month: month.month)
                                    } label: {
                                        MonthRow(month: month)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("时光机")
            .toolbar {
                if FeatureToggles.showCleanupResetControls {
                    Button("重置") { showingResetAlert = true }
                }
            }
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
}

private struct MonthRow: View {
    let month: MonthInfo

    private var monthTitle: String {
        String(format: "%02d 月", month.month)
    }

    private var detailText: String {
        let pending = month.pendingDeleteCount
        let confirmed = month.confirmedCount
        if pending == 0 && confirmed == 0 {
            return "尚未整理"
        }
        return "待删 \(pending) · 已完成 \(confirmed)"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(monthTitle)
                    .font(.headline)
                Text(month.status.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ProgressView(value: month.progress)
                .progressViewStyle(.linear)
                .frame(width: 90)
        }
        .padding(.vertical, 6)
    }
}

private struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
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
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.8))
                .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
        )
    }
}
