import SwiftUI
import Photos

struct LargeFilesView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sortDescending: Bool = true

    private var largeItems: [PhotoItem] {
        let base = viewModel.items.filter { $0.isLargeFile }
        let sorted = base.sorted {
            sortDescending ? $0.fileSize > $1.fileSize : $0.fileSize < $1.fileSize
        }
        // 设计稿中展示“占用空间前 10 名”
        return Array(sorted.prefix(10))
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ModalNavigationHeader(
                    title: "大文件清理",
                    onClose: { dismiss() }
                )

                headerSection

                if largeItems.isEmpty {
                    Spacer()
                    Text("未检测到大文件")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let first = largeItems.first {
                                heroCard(for: first)
                            }

                            if largeItems.count > 1 {
                                VStack(spacing: 12) {
                                    ForEach(Array(largeItems.dropFirst()), id: \.id) { item in
                                        listRow(for: item)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("占用空间前 10 名")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sortDescending.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("排序")
                        .font(.system(size: 11, weight: .bold))
                    Image(systemName: sortDescending ? "arrow.down.to.line.compact" : "arrow.up.to.line.compact")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(Color("brand-start"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // 大卡片：展示第一名大文件
    private func heroCard(for item: PhotoItem) -> some View {
        let isSelected = viewModel.pendingDeletionItems.contains(where: { $0.id == item.id })

        return Button {
            viewModel.setDeletion(item, to: !isSelected)
        } label: {
            ZStack(alignment: .bottomLeading) {
                AssetThumbnailView(
                    asset: item.asset,
                    imageManager: viewModel.imageManager,
                    contentMode: .aspectFill
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipped()

                LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.asset.originalFilename)
                        .font(.system(size: 14, weight: .bold))
                    Text(heroSubtitle(for: item))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .foregroundColor(.white)
                .padding(.leading, 12)
                .padding(.bottom, 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(item.fileSize.fileSizeDescription)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )

                    ZStack {
                        Circle()
                            .fill(isSelected ? Color("brand-start") : Color.clear)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.7), lineWidth: 2)
                            )

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 26, height: 26)
                }
                .padding(.trailing, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .background(Color(UIColor.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func listRow(for item: PhotoItem) -> some View {
        let isSelected = viewModel.pendingDeletionItems.contains(where: { $0.id == item.id })

        return Button {
            viewModel.setDeletion(item, to: !isSelected)
        } label: {
            HStack(spacing: 12) {
                AssetThumbnailView(
                    asset: item.asset,
                    imageManager: viewModel.imageManager,
                    contentMode: .aspectFill
                )
                .frame(width: 48, height: 48)
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.asset.originalFilename)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    if let date = item.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(item.fileSize.fileSizeDescription)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color("brand-start"))
            }
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color("brand-start").opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func heroSubtitle(for item: PhotoItem) -> String {
        var parts: [String] = []
        if let date = item.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            parts.append(formatter.string(from: date))
        }
        if item.isVideo {
            parts.append("视频")
        }
        return parts.joined(separator: " • ")
    }
}
