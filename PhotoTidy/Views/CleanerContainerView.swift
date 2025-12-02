import SwiftUI

struct CleanerContainerView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showTrashSheet = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if viewModel.currentItem != nil {
                VStack(spacing: 12) {
                    HStack {
                        SwipeDateHeaderView(date: viewModel.currentItem?.creationDate)
                        AlbumFilterMenu(viewModel: viewModel)
                    }
                    .padding(.horizontal, 20)

                    CardStackView(viewModel: viewModel)
                        .frame(height: 540)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 8)
            } else if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.1)
                Spacer()
            } else {
                Spacer()
                NoMorePhotosView()
                Spacer()
            }

            Spacer()

            PhotoMetaView(viewModel: viewModel)
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showTrashSheet) {
            TrashView(viewModel: viewModel)
                .presentationDetents([.fraction(0.5), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.isShowingSuccessSummary) {
            SuccessSummaryView(viewModel: viewModel)
        }
    }
}

private extension CleanerContainerView {
    var topBar: some View {
        ZStack(alignment: .topTrailing) {
            ModalNavigationHeader(
                title: viewModel.currentFilter.rawValue,
                onClose: { viewModel.hideCleaner() }
            )

            TrashButton(
                pendingCount: viewModel.pendingDeletionItems.count,
                action: { showTrashSheet = true }
            )
            .padding(.trailing, 24)
            .padding(.top, 18)
        }
        .padding(.bottom, 6)
    }
}

private struct NoMorePhotosView: View {
    var body: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(Color.green.opacity(0.7))
            Text("整理完成")
               .font(.title).bold()
               .foregroundColor(.primary)
            Text("该分类下没有更多照片了")
               .font(.subheadline)
               .foregroundColor(.secondary)
       }
    }
}

private struct LoadingPhotosView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
            Text("正在准备您的照片…")
                .font(.headline)
                .foregroundColor(.primary)
            Text("首次加载相册可能稍慢，请耐心等待。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
    }
}

private struct PhotoMetaView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        VStack {
            if let item = viewModel.currentItem {
                Text(item.asset.originalFilename)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.fileSizeInMB) • \(item.creationDate?.formatted(date: .long, time: .omitted) ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 60)
        .opacity(viewModel.currentItem != nil ? 1 : 0)
    }
}

/// 顶部日期栏：显示「2023年 10月」+「昨天」类似文案
private struct SwipeDateHeaderView: View {
    let date: Date?

    private var formattedText: String {
        guard let date = date else { return "全相册" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月 d日"
        return formatter.string(from: date)
    }

    var body: some View {
        Text(formattedText)
            .font(.headline.weight(.bold))
            .foregroundColor(.primary)
    }
}

private struct AlbumFilterMenu: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        Menu {
            ForEach(viewModel.albumFilters) { filter in
                Button(filter.name) {
                    viewModel.selectAlbumFilter(filter)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundColor(.primary)
        }
    }
}

private struct TrashButton: View {
    let pendingCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)

                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 12, y: -14)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
