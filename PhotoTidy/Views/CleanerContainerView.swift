import SwiftUI

struct CleanerContainerView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showTrashSheet = false

    var body: some View {
        ZStack {
            // 背景做成浅灰到白色的过渡，贴近高保真设计的「phone-frame」感觉
            LinearGradient(
                colors: [Color(UIColor.systemGray6), Color(UIColor.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                CleanerHeader(viewModel: viewModel, showTrashSheet: $showTrashSheet)

                if viewModel.currentItem != nil {
                    VStack(spacing: 12) {
                        SwipeDateHeaderView(date: viewModel.currentItem?.creationDate)

                        CardStackView(viewModel: viewModel)
                            .frame(height: 480)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)
                } else {
                    Spacer()
                    NoMorePhotosView()
                    Spacer()
                }

                Spacer()

                PhotoMetaView(viewModel: viewModel)

                CleanerFooter(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showTrashSheet) {
            PendingDeletionView(viewModel: viewModel)
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
        }
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

private struct PhotoMetaView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        VStack {
            if let item = viewModel.currentItem {
                Text(item.asset.originalFilename)
                    .font(.headline).bold()
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
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [Color(UIColor.systemGray6), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}


private struct CleanerHeader: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Binding var showTrashSheet: Bool
    
    var body: some View {
        HStack {
            Button(action: { viewModel.hideCleaner() }) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            VStack {
                Text(viewModel.currentFilter.rawValue)
                    .font(.headline).bold()
                if viewModel.isAnalyzing {
                    Text("AI 智能识别中...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: { showTrashSheet = true }) {
                ZStack {
                    Image(systemName: "trash")
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                    
                    if !viewModel.pendingDeletionItems.isEmpty {
                        Text("\(viewModel.pendingDeletionItems.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 14, y: -14)
                            .transition(.scale.animation(.spring()))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }
}

private struct CleanerFooter: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    var body: some View {
        HStack {
            Spacer()
            
            // Discard Button
            Button(action: {
                viewModel.markCurrentForDeletion()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.red)
                    .frame(width: 70, height: 70)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

            }
            
            Spacer()
            
            Text("SWIPE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray.opacity(0.5))
            
            Spacer()
            
            // Keep Button
            Button(action: {
                viewModel.keepCurrent()
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color("brand-start"), Color("brand-end")]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: Color("brand-start").opacity(0.4), radius: 10, y: 5)
            }
            
            Spacer()
        }
        .padding(.bottom, 40)
    }
}
