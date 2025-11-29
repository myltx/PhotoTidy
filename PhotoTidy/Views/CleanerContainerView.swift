import SwiftUI

struct CleanerContainerView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showTrashSheet = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if viewModel.isAnalyzing {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                    Text("AI 正在分析中…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
            }

            if viewModel.currentItem != nil {
                VStack(spacing: 12) {
                    SwipeDateHeaderView(date: viewModel.currentItem?.creationDate)

                    CardStackView(viewModel: viewModel)
                        .frame(height: 480)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 8)
            } else if viewModel.isLoading {
                Spacer()
                LoadingPhotosView()
                Spacer()
            } else {
                Spacer()
                NoMorePhotosView()
                Spacer()
            }

            Spacer()

            PhotoMetaView(viewModel: viewModel)

            CleanerFooter(viewModel: viewModel)
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

    private var monthYearText: String {
        guard let date = date else { return "全相册" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }

    private var relativeDayText: String {
        guard let date = date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "今天"
        } else if cal.isDateInYesterday(date) {
            return "昨天"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日"
            return formatter.string(from: date)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(monthYearText)
                .font(.headline.weight(.bold))
                .foregroundColor(.primary)
            if !relativeDayText.isEmpty {
                Text(relativeDayText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .padding(.horizontal, 24)
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

private struct CleanerFooter: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        HStack(spacing: 32) {
            footerButton(
                icon: "xmark",
                foreground: .red,
                background: Color(UIColor.systemBackground),
                action: viewModel.markCurrentForDeletion
            )

            footerButton(
                icon: "arrow.up",
                foreground: .orange,
                background: Color(UIColor.systemBackground),
                action: viewModel.skipCurrent
            )

            footerButton(
                icon: "checkmark",
                foreground: .white,
                background: LinearGradient(
                    gradient: Gradient(colors: [Color("brand-start"), Color("brand-end")]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                action: viewModel.keepCurrent
            )
        }
        .padding(.bottom, 40)
    }

    @ViewBuilder
    private func footerButton<Background: View>(icon: String, foreground: Color, background: Background, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(foreground)
                .frame(width: 70, height: 70)
                .background(background)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
        }
    }
}
