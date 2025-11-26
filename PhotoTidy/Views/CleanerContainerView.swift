import SwiftUI

struct CleanerContainerView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        VStack(spacing: 0) {
            CleanerHeader(viewModel: viewModel)
            
            Spacer()

            if viewModel.currentItem != nil {
                CardStackView(viewModel: viewModel)
                    .frame(height: 480)
                    .padding(.horizontal, 20)
            } else {
                NoMorePhotosView()
            }
            
            Spacer()
            
            PhotoMetaView(viewModel: viewModel)

            CleanerFooter(viewModel: viewModel)
        }
        .background(Color(UIColor.systemBackground))
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


private struct CleanerHeader: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
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
            
            Button(action: { viewModel.showTrash() }) {
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
