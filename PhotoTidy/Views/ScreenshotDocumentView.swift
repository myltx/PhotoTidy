import SwiftUI
import Photos

struct ScreenshotDocumentView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var filterIndex: Int = 0 // 0 = 全部, 1 = 票据/文档, 2 = 文字图片
    @State private var showingTrash = false

    private var docs: [PhotoItem] {
        viewModel.items.filter { $0.isScreenshot || $0.isDocumentLike || $0.isTextImage }
    }

    private var filteredDocs: [PhotoItem] {
        switch filterIndex {
        case 1:
            // 票据/文档：拍摄到的纸张等
            return docs.filter { $0.isDocumentLike }
        case 2:
            // 文字图片：含大量文字（可能是截图或拍照）
            return docs.filter { $0.isTextImage }
        default:
            return docs
        }
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ModalNavigationHeader(
                    title: "文档 & 截图",
                    onClose: { dismiss() }
                )

                header

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredDocs, id: \.id) { item in
                            docRow(for: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .padding(.bottom, 80)
                }
            }
        }
        .sheet(isPresented: $showingTrash) {
            TrashView(viewModel: viewModel)
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
        }
        .safeAreaInset(edge: .bottom) {
            if selectedDocsCount > 0 {
                screenshotToolbar
            } else {
                Color.clear.frame(height: 0)
            }
        }
    }

    private var header: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip(title: "全部", index: 0)
                filterChip(title: "票据", index: 1)
                filterChip(title: "文字图片", index: 2)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(title: String, index: Int) -> some View {
        let isActive = filterIndex == index
        return Text(title)
            .font(.system(size: 11, weight: isActive ? .bold : .medium))
            .foregroundColor(isActive ? Color("brand-start") : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(isActive ? Color("brand-start").opacity(0.15) : Color(UIColor.secondarySystemFill))
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    filterIndex = index
                }
            }
    }

    private func docRow(for item: PhotoItem) -> some View {
        let isSelected = viewModel.pendingDeletionItems.contains(where: { $0.id == item.id })
        let isDoc = item.isDocumentLike && !item.isScreenshot

        return Button {
            viewModel.setDeletion(item, to: !isSelected)
        } label: {
            HStack(spacing: 12) {
                AssetThumbnailView(
                    asset: item.asset,
                    target: .dashboardCard
                )
                .frame(width: 60, height: 80)
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.asset.originalFilename)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)

                    Text(docSubtitle(for: item, isDoc: isDoc))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(isSelected ? Color("brand-start") : Color.clear)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? Color("brand-start") : Color(UIColor.systemGray4),
                                    lineWidth: 2
                                )
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color("brand-start").opacity(0.12) : Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected ? Color("brand-start").opacity(0.6) : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func docSubtitle(for item: PhotoItem, isDoc: Bool) -> String {
        if let date = item.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let dateText = formatter.string(from: date)
            if isDoc {
                return "\(dateText) • 文档"
            } else if item.isScreenshot {
                return "\(dateText) • 截图"
            }
            return dateText
        } else {
            return isDoc ? "文档" : (item.isScreenshot ? "截图" : "未知时间")
        }
    }

    private var selectedDocsCount: Int {
        viewModel.pendingDeletionItems.filter { $0.isScreenshot || $0.isDocumentLike || $0.isTextImage }.count
    }

    private var screenshotToolbar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选择 \(selectedDocsCount) 项")
                    .font(.system(size: 13, weight: .semibold))
                Text("查看待删区以统一处理")
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
