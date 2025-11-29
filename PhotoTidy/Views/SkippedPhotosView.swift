import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SkippedPhotosView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SkippedSourceCategory? = nil
    @State private var isSelecting: Bool = false
    @State private var selection = Set<String>()
    @State private var showingClearAlert = false
    @State private var previewItem: PhotoItem?
    @State private var shouldHideTabBar = true
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    private var bottomSafePadding: CGFloat {
        #if canImport(UIKit)
        let inset = UIApplication.pht_keyWindow?.safeAreaInsets.bottom ?? 0
        return max(inset, 8)
        #else
        return 8
        #endif
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGray6)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(.ultraThinMaterial)
                    
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
                                        HStack {
                                            Text(section.title)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 18) {
                                            ForEach(section.sourceGroups) { group in
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text(group.displayTitle)
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(.secondary)
                                                    LazyVGrid(columns: gridColumns, spacing: 12) {
                                                        ForEach(group.entries) { entry in
                                                            SkippedPhotoCell(
                                                                entry: entry,
                                                                isSelected: selection.contains(entry.record.photoId),
                                                                isSelecting: isSelecting,
                                                                viewModel: viewModel
                                                            )
                                                            .contentShape(Rectangle())
                                                            .onTapGesture {
                                                                if isSelecting {
                                                                    toggleSelection(for: entry.record.photoId)
                                                                } else if let photo = entry.photo {
                                                                    previewItem = photo
                                                                }
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
                            
                            Color.clear.frame(height: 20)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationBarHidden(true)
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
            .toolbar(shouldHideTabBar ? .hidden : .visible, for: .tabBar)
            .fullScreenCover(item: $previewItem) { item in
                FullScreenPreviewView(item: item, viewModel: viewModel)
            }
        }
        .onAppear { shouldHideTabBar = true }
        .onDisappear { shouldHideTabBar = false }
    }
    
    private var header: some View {
        HStack {
            Button {
                shouldHideTabBar = false
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("跳过中心")
                .font(.system(size: 18, weight: .bold))
            
            Spacer()
        }
    }
    
    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.purple)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
            Text("\(viewModel.skippedPhotoRecords.count) 张待确认照片")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text("这些是你在智能清理、时光机等模式中选择“跳过”的照片，重新审视以确保没有遗漏。")
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
    
    
    private var selectionActionBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text(isSelecting ? "已选择 \(selection.count) 项" : "选择照片进行补处理")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(isSelecting ? "取消" : "全选") {
                    if isSelecting {
                        exitSelectionMode()
                    } else {
                        enterSelectionMode(selectAll: true)
                    }
                }
                .font(.system(size: 12, weight: .bold))
            }
            
            HStack(spacing: 12) {
                actionPill(
                    title: "加入待删区",
                    icon: "trash.fill",
                    style: .destructive,
                    isEnabled: !selection.isEmpty
                ) {
                    viewModel.confirmDeletionForSkipped(ids: Array(selection))
                    exitSelectionMode()
                }
                
                actionPill(
                    title: "恢复到主流程",
                    icon: "arrow.uturn.backward",
                    style: .neutral,
                    isEnabled: !selection.isEmpty
                ) {
                    viewModel.reinstateSkippedPhotos(ids: Array(selection))
                    exitSelectionMode()
                }
            }
            
            actionPill(
                title: "确认不需要删除",
                icon: "checkmark.circle.fill",
                style: .neutral,
                isEnabled: !selection.isEmpty
            ) {
                viewModel.acknowledgeSkippedPhotos(ids: Array(selection))
                exitSelectionMode()
            }
        }
    }

    @ViewBuilder
    private var selectionBarInset: some View {
        if isSelecting {
            VStack(spacing: 0) {
                selectionActionBar
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .padding(.bottom, bottomSafePadding)
            }
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Color.clear.frame(height: 0)
        }
    }
    
    private func actionPill(title: String, icon: String, style: ActionStyle, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(style == .destructive ? .white : .primary)
            .background(style == .destructive ? Color.red : Color(UIColor.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
    
    private enum ActionStyle {
        case destructive
        case neutral
    }
    
    private var filterBar: some View {
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
            
            Text(summaryText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var availableCategories: [SkippedSourceCategory] {
        let categories = Set(viewModel.skippedPhotoRecords.map { $0.source.category })
        return categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var filteredEntries: [SkippedPhotoEntry] {
        viewModel.skippedPhotoRecords
            .filter { record in
                if let category = selectedCategory, record.source.category != category { return false }
                return true
            }
            .compactMap { record in
                let item = viewModel.items.first { $0.id == record.photoId }
                return SkippedPhotoEntry(record: record, photo: item, category: record.source.category)
            }
    }

    private var groupedSections: [SkippedSection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { entry -> Date in
            calendar.startOfDay(for: entry.record.timestamp)
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

    private func groupedBySource(entries: [SkippedPhotoEntry]) -> [SkippedSourceGroup] {
        let groups = Dictionary(grouping: entries) { $0.category }
        return groups.map { category, items in
            let sortedItems = items.sorted { $0.record.timestamp > $1.record.timestamp }
            return SkippedSourceGroup(category: category, entries: sortedItems)
        }
        .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }
    
    private var summaryText: String {
        let total = filteredEntries.count
        return "共 \(total) 项"
    }
    
    private var emptyState: some View {
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
    
    private var unprocessedCount: Int {
        viewModel.skippedPhotoRecords.count
    }
    
    private func toggleSelection(for id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
    
    private func enterSelectionMode(selectAll: Bool = false) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isSelecting = true
        }
        if selectAll {
            selection = Set(filteredEntries.map { $0.record.photoId })
        } else {
            selection.removeAll()
        }
    }
    
    private func exitSelectionMode() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isSelecting = false
        }
        selection.removeAll()
    }
    
}

private struct SkippedPhotoEntry: Identifiable {
    let record: SkippedPhotoRecord
    let photo: PhotoItem?
    let category: SkippedSourceCategory
    
    var id: String { record.photoId }
}

private struct SkippedSection: Identifiable {
    let date: Date
    let title: String
    let sourceGroups: [SkippedSourceGroup]
    
    var id: TimeInterval { date.timeIntervalSince1970 }
}

private struct SkippedSourceGroup: Identifiable {
    let category: SkippedSourceCategory
    let entries: [SkippedPhotoEntry]
    
    var id: String { category.id }
    var displayTitle: String { "\(category.title) · \(entries.count) 张" }
}

private struct SkippedPhotoCell: View {
    let entry: SkippedPhotoEntry
    let isSelected: Bool
    let isSelecting: Bool
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let photo = entry.photo {
                AssetThumbnailView(
                    asset: photo.asset,
                    imageManager: viewModel.imageManager
                )
                .aspectRatio(1, contentMode: .fill)
                .clipped()
            } else {
                placeholder
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(shortTimestamp)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
            }
            .padding(8)
            
            if entry.record.isProcessed {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.green)
                        .padding(8)
                }
            }
            
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
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.systemGray5))
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                Text("资源不可用")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 120)
    }
    
    private var shortTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: entry.record.timestamp)
    }
}

#if canImport(UIKit)
private extension UIApplication {
    static var pht_keyWindow: UIWindow? {
        shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif
