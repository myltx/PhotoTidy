import SwiftUI
import UIKit

struct SkippedPhotosView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: SkippedSourceCategory?
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var showingClearAlert = false
    @State private var previewMetadata: PhotoAssetMetadata?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    infoCard
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    filterBar
                        .padding(.horizontal, 24)

                    if groupedSections.isEmpty {
                        emptyState
                            .padding(.top, 80)
                            .padding(.horizontal, 40)
                    } else {
                        ForEach(groupedSections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 24)

                                VStack(alignment: .leading, spacing: 18) {
                                    ForEach(section.sourceGroups) { group in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(group.displayTitle)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.secondary)
                                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                                ForEach(group.entries) { entry in
                                                    SkippedPhotoCell(
                                                        metadata: entry.metadata,
                                                        isSelected: selection.contains(entry.metadata.id),
                                                        isSelecting: isSelecting
                                                    )
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        if isSelecting {
                                                            toggleSelection(for: entry.metadata.id)
                                                        } else {
                                                            previewMetadata = entry.metadata
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }

                    Color.clear.frame(height: 20)
                }
            }
            .scrollIndicators(.hidden)
        }
        .alert("清空全部跳过记录？", isPresented: $showingClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                viewModel.clearSkippedRecords()
                selection.removeAll()
            }
        } message: {
            Text("仅会移除跳过记录，并不会修改照片或待删区。")
        }
        .safeAreaInset(edge: .bottom) {
            selectionBarInset
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $previewMetadata) { metadata in
            NavigationStack {
                ZStack(alignment: .topLeading) {
                    MediaContentView(metadata: metadata)
                    Text(metadata.mediaBadgeText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding()
                }
                .navigationTitle("预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("关闭") {
                            previewMetadata = nil
                        }
                    }
                }
            }
        }
        .navigationTitle("待确认照片")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(UIColor.systemBackground))
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension SkippedPhotosView {
    var entries: [SkippedEntry] {
        viewModel.skippedItems.map { metadata in
            SkippedEntry(metadata: metadata, category: SkippedSourceCategory(metadata: metadata))
        }
    }

    var filteredEntries: [SkippedEntry] {
        entries.filter { entry in
            guard let category = selectedCategory else { return true }
            return entry.category == category
        }
    }

    var groupedSections: [SkippedSection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { entry -> Date in
            calendar.startOfDay(for: entry.metadata.captureDate)
        }

        return groups.map { date, entries in
            let title: String = {
                if calendar.isDateInToday(date) { return "今天" }
                if calendar.isDateInYesterday(date) { return "昨天" }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = "M月d日"
                return formatter.string(from: date)
            }()
            let sourceGroups = groupedBySource(entries: entries)
            return SkippedSection(date: date, title: title, sourceGroups: sourceGroups)
        }
        .sorted { $0.date > $1.date }
    }

    func groupedBySource(entries: [SkippedEntry]) -> [SkippedSourceGroup] {
        let groups = Dictionary(grouping: entries) { $0.category }
        return groups.map { category, items in
            let sortedItems = items.sorted { $0.metadata.captureDate > $1.metadata.captureDate }
            return SkippedSourceGroup(category: category, entries: sortedItems)
        }
        .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }

    var availableCategories: [SkippedSourceCategory] {
        let categories = Set(entries.map(\.category))
        return categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.purple)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(viewModel.skippedItems.count) 张待确认照片")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text("这些是你在滑动模式、相似照片等流程中选择“跳过”的记录，重新审视以确保没有遗漏。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.purple.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }

    var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Menu {
                    Button("全部来源") { selectedCategory = nil }
                    if !availableCategories.isEmpty {
                        Divider()
                    }
                    ForEach(availableCategories) { category in
                        Button(category.title) { selectedCategory = category }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedCategory?.title ?? "全部来源")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemGray5))
                    .clipShape(Capsule())
                }

                Spacer()

                Button {
                    if isSelecting {
                        exitSelectionMode()
                    } else {
                        enterSelectionMode()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelecting ? "xmark.circle.fill" : "square.and.pencil")
                        Text(isSelecting ? "退出选择" : "选择模式")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemGray5))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Text("共 \(filteredEntries.count) 项")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.down.forward")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text("暂无跳过记录")
                .font(.headline)
            Text("在任何模式中选择“跳过”后，这里会保留一份记录以便之后回顾。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    var selectionBarInset: some View {
        if isSelecting {
            VStack(spacing: 12) {
                HStack {
                    Text(selection.isEmpty ? "选择照片进行处理" : "已选择 \(selection.count) 项")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(selection.isEmpty ? "全选" : "取消") {
                        if selection.isEmpty {
                            enterSelectionMode(selectAll: true)
                        } else {
                            exitSelectionMode()
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                }

                HStack(spacing: 12) {
                    decisionButton(
                        title: "加入待删区",
                        icon: "trash.fill",
                        tint: .red,
                        action: { viewModel.confirmDeletionForSkipped(ids: Array(selection)); exitSelectionMode() }
                    )
                    decisionButton(
                        title: "恢复主流程",
                        icon: "arrow.uturn.backward",
                        tint: .orange,
                        action: { viewModel.reinstateSkippedPhotos(ids: Array(selection)); exitSelectionMode() }
                    )
                    decisionButton(
                        title: "确认保留",
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        action: { viewModel.acknowledgeSkippedPhotos(ids: Array(selection)); exitSelectionMode() }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12 + safeAreaBottomInset)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 0.5)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Color.clear.frame(height: 0)
        }
    }

    func decisionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tint))
                Text(title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .opacity(selection.isEmpty ? 0.5 : 1)
        }
        .disabled(selection.isEmpty)
    }

    var safeAreaBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }

    func toggleSelection(for id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func enterSelectionMode(selectAll: Bool = false) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isSelecting = true
        }
        if selectAll {
            selection = Set(filteredEntries.map { $0.metadata.id })
        }
    }

    func exitSelectionMode() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isSelecting = false
        }
        selection.removeAll()
    }
}

private struct SkippedEntry: Identifiable {
    let metadata: PhotoAssetMetadata
    let category: SkippedSourceCategory

    var id: String { metadata.id }
}

private struct SkippedSection: Identifiable {
    let date: Date
    let title: String
    let sourceGroups: [SkippedSourceGroup]

    var id: TimeInterval { date.timeIntervalSince1970 }
}

private struct SkippedSourceGroup: Identifiable {
    let category: SkippedSourceCategory
    let entries: [SkippedEntry]

    var id: String { category.id }
    var displayTitle: String { "\(category.title) · \(entries.count) 张" }
}

private enum SkippedSourceCategory: String, CaseIterable, Identifiable {
    case timeMachine
    case smart
    case similar
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeMachine: return "时光机"
        case .smart: return "全相册整理"
        case .similar: return "相似照片"
        case .other: return "其他来源"
        }
    }

    var sortOrder: Int {
        switch self {
        case .timeMachine: return 0
        case .smart: return 1
        case .similar: return 2
        case .other: return 3
        }
    }

    init(metadata: PhotoAssetMetadata) {
        if metadata.groupIdentifier != nil {
            self = .similar
        } else if metadata.tags.contains(.blurred) || metadata.tags.contains(.document) || metadata.tags.contains(.screenshot) {
            self = .other
        } else {
            self = .smart
        }
    }
}

private struct SkippedPhotoCell: View {
    let metadata: PhotoAssetMetadata
    let isSelected: Bool
    let isSelecting: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            AssetPreviewView(metadata: metadata, cornerRadius: 18, showOverlay: false)
                .frame(height: 120)

            Text(shortTimestamp)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .padding(8)

            if isSelecting {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                            .padding(8)
                        Spacer()
                    }
                }
            }
        }
        .frame(height: 120)
        .background(Color(UIColor.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    var shortTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: metadata.captureDate)
    }
}
