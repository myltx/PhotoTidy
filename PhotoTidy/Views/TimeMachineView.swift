import SwiftUI
import Photos

struct TimeMachineView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    private var sections: [TimelineSection] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"

        let grouped = Dictionary(grouping: viewModel.items) { (item: PhotoItem) -> DateComponents in
            guard let date = item.creationDate else {
                return DateComponents(year: 0, month: 0)
            }
            return calendar.dateComponents([.year, .month], from: date)
        }

        return grouped.map { key, value in
            let items = value.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            guard let year = key.year, let month = key.month else {
                return TimelineSection(
                    id: "unknown",
                    title: "未标记日期",
                    date: .distantPast,
                    items: items
                )
            }
            let sectionDate = calendar.date(from: DateComponents(year: year, month: month)) ?? .distantPast
            let title = formatter.string(from: sectionDate)
            return TimelineSection(
                id: "\(year)-\(month)",
                title: title,
                date: sectionDate,
                items: items
            )
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 46))
                            .foregroundColor(.secondary)
                        Text("暂无可查看的照片")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 100)
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(header: Text(section.title).font(.headline)) {
                                NavigationLink {
                                    TimeMachineMonthView(section: section, viewModel: viewModel)
                                } label: {
                                    TimeMachineSectionRow(section: section, viewModel: viewModel)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("时光机")
        }
    }
}

private struct TimeMachineSectionRow: View {
    let section: TimelineSection
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        HStack(spacing: 12) {
            if let cover = section.items.first {
                AssetThumbnailView(
                    asset: cover.asset,
                    imageManager: viewModel.imageManager,
                    contentMode: .aspectFill
                )
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.systemGray5))
                    .frame(width: 70, height: 70)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.headline)
                Text("\(section.items.count) 张照片")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct TimeMachineMonthView: View {
    let section: TimelineSection
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var previewItem: PhotoItem?

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(section.items) { item in
                    TimelinePhotoCell(item: item, viewModel: viewModel) {
                        previewItem = item
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
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
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct TimelineSection: Identifiable {
    let id: String
    let title: String
    let date: Date
    let items: [PhotoItem]
}
