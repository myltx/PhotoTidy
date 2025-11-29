import SwiftUI

struct SkippedPhotosView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var selectedSource: SkippedPhotoSource? = nil
    @State private var processedFilter: ProcessedFilter = .unprocessed
    @State private var isSelecting: Bool = false
    @State private var selection = Set<String>()
    @State private var showingClearAlert = false
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                filterBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                
                if entries.isEmpty {
                    emptyState
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(entries) { entry in
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
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("跳过中心")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isSelecting ? "完成" : "选择") {
                        isSelecting.toggle()
                        if !isSelecting {
                            selection.removeAll()
                        }
                    }
                    .disabled(entries.isEmpty)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        showingClearAlert = true
                    }
                    .disabled(viewModel.skippedPhotoRecords.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selection.isEmpty {
                    selectionActions
                } else {
                    Color.clear.frame(height: 0)
                }
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
        }
    }
    
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
    
    private var selectionActions: some View {
        VStack {
            Divider()
            HStack(spacing: 12) {
                Button {
                    viewModel.markSkippedRecordsProcessed(ids: Array(selection))
                    selection.removeAll()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("标记已处理")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                
                Button {
                    viewModel.deleteSkippedRecords(ids: Array(selection))
                    selection.removeAll()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("删除记录")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
    
    private var entries: [SkippedPhotoEntry] {
        viewModel.skippedPhotoRecords
            .filter { record in
                if let source = selectedSource, record.source != source {
                    return false
                }
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
    
    private var summaryText: String {
        let total = entries.count
        let processed = entries.filter { $0.record.isProcessed }.count
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
    
    private func toggleSelection(for id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
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
