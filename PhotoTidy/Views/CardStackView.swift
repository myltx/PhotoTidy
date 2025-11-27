import SwiftUI

struct CardStackView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { _ in
            let start = viewModel.currentIndex
            let end = min(start + 3, viewModel.sessionItems.count)
            let stackSlice = Array(viewModel.sessionItems[start..<end])

            ZStack {
                ForEach(Array(stackSlice.enumerated()), id: \.element.id) { localIndex, item in
                    // 让 indexInStack = 0 始终表示最上层卡片
                    let indexInStack = stackSlice.count - 1 - localIndex
                    PhotoCardViewWrapper(
                        item: item,
                        viewModel: viewModel,
                        dragOffset: $dragOffset,
                        indexInStack: indexInStack
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: viewModel.currentIndex) { _ in
            dragOffset = .zero
        }
    }
}

private struct PhotoCardViewWrapper: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Binding var dragOffset: CGSize

    let indexInStack: Int // 0 = top card

    private var isTopCard: Bool { indexInStack == 0 }
    private var scale: CGFloat { 1.0 - (CGFloat(indexInStack) * 0.05) }
    private var yOffset: CGFloat { CGFloat(indexInStack) * 18 }
    private var rotation: Double { Double(dragOffset.width / 20) }

    var body: some View {
        GeometryReader { geometry in
            PhotoCardView(item: item, viewModel: viewModel)
                .scaleEffect(isTopCard ? 1.0 : scale)
                .offset(y: isTopCard ? 0 : yOffset)
                .offset(isTopCard ? dragOffset : .zero)
                .rotationEffect(isTopCard ? .degrees(rotation) : .degrees(0))
                .animation(.spring(), value: dragOffset)
                .contentShape(Rectangle())
                .gesture(
                    isTopCard ?
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            handleDragEnd(value, geometry: geometry)
                        }
                    : nil
                )
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value, geometry: GeometryProxy) {
        let swipeThreshold = geometry.size.width * 0.3
        let translation = value.translation

        if translation.width > swipeThreshold {
            // 右滑：保留
            viewModel.keepCurrent()
        } else if translation.width < -swipeThreshold {
            // 左滑：加入待删区
            viewModel.markCurrentForDeletion()
        } else if translation.height < -swipeThreshold {
            // 上滑：跳过
            viewModel.moveToNext()
        }

        withAnimation(.spring()) {
            dragOffset = .zero
        }
    }
}

