import SwiftUI

struct SkippedPhotosView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSource: SkippedPhotoSource? = nil
    @State private var processedFilter: ProcessedFilter = .unprocessed
    @State private var isSelecting: Bool = false
    @State private var selection = Set<String>()
    @State private var showingClearAlert = false
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
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
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(section.title)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.primary)
                                                Text(section.sourceText)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                        }
                                        
                                        LazyVGrid(columns: gridColumns, spacing: 12) {
                                            ForEach(section.entries) { entry in
                                                SkippedPhotoCell(
                                                    entry: entry,
                                                    isSelected: selection.contains(entry.record.photoId),
                                                    isSelecting: isSelecting,
                                                    viewModel: viewModel
                                                )
                                                .onTapGesture {
                                                    guard isSelecting else { return }
                                                    toggleSelection(for: entry.record.photoId)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            }
                            
                            Color.clear.frame(height: 140)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                
                bottomActions
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
            .toolbar(.hidden, for: .tabBar)
        }
    }
    
    private var header: some View {
        HStack {
            Button {
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
            
            Button("清空") {
                showingClearAlert = true
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .disabled(viewModel.skippedPhotoRecords.isEmpty)
        }
    }
    
    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.purple)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(unprocessedCount) 张待确认照片")
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
    
    private var bottomActions: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 16) {
                Menu {
                    if !isSelecting {
                        Button("进入选择模式") { enterSelectionMode() }
                    } else {
                        Button("标记已处理 (\(selection.count))") {
                            viewModel.markSkippedRecordsProcessed(ids: Array(selection))
                            selection.removeAll()
                        }
                        .disabled(selection.isEmpty)
                        
                        Button("删除选中 (\(selection.count))", role: .destructive) {
                            viewModel.deleteSkippedRecords(ids: Array(selection))
                            selection.removeAll()
                        }
                        .disabled(selection.isEmpty)
                        
                        Button("退出选择模式", role: .cancel) {
                            exitSelectionMode()
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 60, height: 60)
                        .background(Color(UIColor.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                
                Button {
                    startRevisit()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("开始重新审视 (\(unprocessedCount))")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        LinearGradient(
                            colors: [Color("brand-start"), Color("brand-end")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                }
                .disabled(unprocessedCount == 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
    }
    
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Menu {
                    Button("全部来源") { selectedSource = nil }
                    Divider()
                    ForEach(SkippedPhotoSource.allCases) { source in
                        Button(source.title) { selectedSource = source }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedSource?.title ?? "全部来源")
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
                
                Picker("", selection: $processedFilter) {
                    ForEach(ProcessedFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            
            Text(summaryText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
// remove section?
    
    private var filteredEntries: [SkippedPhotoEntry] {
        viewModel.skippedPhotoRecords
            .filter { record in
                if let source = selectedSource, record.source != source { return false }
                switch processedFilter {
                case .all: return true
                case .processed: return record.isProcessed
                case .unprocessed: return !record.isProcessed
                }
            }
            .compactMap { record in
                let item = viewModel.items.first { $0.id == record.photoId }
                return SkippedPhotoEntry(record: record, photo: item)
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
            let sources = Set(entries.map { $0.record.source.title }).sorted()
            let sourceText = sources.isEmpty ? "来自: --" : "来自: " + sources.joined(separator: "、")
            return SkippedSection(date: date, title: title, sourceText: sourceText, entries: entries)
        }
        .sorted { $0.date > $1.date }
    }
    
    private var summaryText: String {
        let total = filteredEntries.count
        let processed = filteredEntries.filter { $0.record.isProcessed }.count
        return "共 \(total) 项 · 已处理 \(processed) 项"
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
        viewModel.skippedPhotoRecords.filter { !$0.isProcessed }.count
    }
    
    private func toggleSelection(for id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
    
    private func enterSelectionMode(selectAll: Bool = false) {
        isSelecting = true
        if selectAll {
            selection = Set(filteredEntries.map { $0.record.photoId })
        } else {
            selection.removeAll()
        }
    }
    
    private func exitSelectionMode() {
        isSelecting = false
        selection.removeAll()
    }
    
    private var unprocessedEntries: [SkippedPhotoEntry] {
        viewModel.skippedPhotoRecords
            .filter { !$0.isProcessed }
            .compactMap { record in
                let item = viewModel.items.first { $0.id == record.photoId }
                return SkippedPhotoEntry(record: record, photo: item)
            }
    }
    
    private func startRevisit() {
        guard unprocessedCount > 0 else { return }
        selectedSource = nil
        processedFilter = .unprocessed
        DispatchQueue.main.async {
            enterSelectionMode(selectAll: true)
        }
    }
    
    private enum ProcessedFilter: String, CaseIterable, Identifiable {
        case all
        case unprocessed
        case processed
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .all: return "全部"
            case .unprocessed: return "未处理"
            case .processed: return "已处理"
            }
        }
    }
}

private struct SkippedPhotoEntry: Identifiable {
    let record: SkippedPhotoRecord
    let photo: PhotoItem?
    
    var id: String { record.photoId }
}

private struct SkippedSection: Identifiable {
    let date: Date
    let title: String
    let sourceText: String
    let entries: [SkippedPhotoEntry]
    
    var id: TimeInterval { date.timeIntervalSince1970 }
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
                Text(entry.record.source.title)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.4))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                Text(shortTimestamp)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.9))
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
