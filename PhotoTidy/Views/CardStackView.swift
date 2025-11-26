import SwiftUI

struct CardStackView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    
    // Drag state for the top card
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // The stack of cards
            ForEach(Array(viewModel.sessionItems.enumerated()), id: \.element.id) { index, item in
                if index >= viewModel.currentIndex && index < viewModel.currentIndex + 3 {
                    PhotoCardViewWrapper(
                        item: item,
                        viewModel: viewModel,
                        dragOffset: $dragOffset,
                        indexInStack: index - viewModel.currentIndex
                    )
                }
            }
        }
        .onChange(of: viewModel.currentIndex) { _, _ in
            dragOffset = .zero
        }
    }
}

private struct PhotoCardViewWrapper: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Binding var dragOffset: CGSize
    
    let indexInStack: Int // 0 is top, 1 is next, etc.
    
    // Calculated properties for styling based on stack position
    private var isTopCard: Bool { indexInStack == 0 }
    private var scale: CGFloat { 1.0 - (CGFloat(indexInStack) * 0.05) }
    private var yOffset: CGFloat { CGFloat(indexInStack) * 15 }
    private var rotation: Double { Double(dragOffset.width / 20) }

    var body: some View {
        GeometryReader { geometry in
            PhotoCardView(item: item, viewModel: viewModel)
                .scaleEffect(isTopCard ? 1.0 : scale)
                .offset(y: isTopCard ? 0 : yOffset)
                .offset(isTopCard ? dragOffset : .zero)
                .rotationEffect(isTopCard ? .degrees(rotation) : .degrees(0))
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
        let swipeThreshold = geometry.size.width * 0.4
        let translation = value.translation
        
        if translation.width > swipeThreshold {
            // Keep
            viewModel.keepCurrent()
        } else if translation.width < -swipeThreshold {
            // Delete
            viewModel.markCurrentForDeletion()
        }
        
        withAnimation(.spring()) {
            dragOffset = .zero
        }
    }
}
