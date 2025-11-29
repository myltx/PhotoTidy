import SwiftUI
import Photos

struct LargeFilesView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sortDescending: Bool = true
    @State private var showingTrash: Bool = false
    @State private var selectedCountOption: LargeFileCountOption = .ten

    private var selectedLargeItems: [PhotoItem] {
        viewModel.pendingDeletionItems.filter { $0.isLargeFile }
    }

    private var selectedTotalSize: Int {
        selectedLargeItems.reduce(0) { $0 + $1.fileSize }
    }
    private var largeItems: [PhotoItem] {
        let sorted = viewModel.items
            .filter { $0.isLargeFile }
            .sorted { sortDescending ? $0.fileSize > $1.fileSize : $0.fileSize < $1.fileSize }
        return Array(sorted.prefix(selectedCountOption.limit))
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
                    VStack(spacing: 8) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("未检测到大文件")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
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
        .sheet(isPresented: $showingTrash) {
            TrashView(viewModel: viewModel)
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
        }
        .safeAreaInset(edge: .bottom) {
            selectionToolbar
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("显示前 \(selectedCountOption.displayText) 个大文件")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            rankingButton
            sortButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }
    
    private var sortButton: some View {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var rankingButton: some View {
        Menu {
            ForEach(LargeFileCountOption.allCases, id: \.self) { option in
                Button(action: { selectedCountOption = option }) {
                    HStack {
                        Text(option.title)
                        if option == selectedCountOption {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("TOP \(selectedCountOption.displayText)")
                    .font(.system(size: 11, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(Color("brand-start"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .menuStyle(.automatic)
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

                    if isSelected {
                        Text("已选择")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color("brand-start").opacity(0.7))
                            .clipShape(Capsule())
                    }
                }
                .padding(.trailing, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .background(Color(UIColor.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color("brand-start") : Color.clear, lineWidth: 3)
            )
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
                    if let date = item.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(isSelected ? Color("brand-start") : .primary)

                Spacer()

                Text(item.fileSize.fileSizeDescription)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isSelected ? Color("brand-start") : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color("brand-start").opacity(0.12) : Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color("brand-start").opacity(0.6) : Color.black.opacity(0.05), lineWidth: 1)
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
    
    @ViewBuilder
    private var selectionToolbar: some View {
        if selectedLargeItems.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已选择 \(selectedLargeItems.count) 个大文件")
                        .font(.system(size: 13, weight: .semibold))
                    Text("总计 \(selectedTotalSize.fileSizeDescription)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    showingTrash = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("查看待删")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color("brand-start"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)
            .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        }
    }
}
    
