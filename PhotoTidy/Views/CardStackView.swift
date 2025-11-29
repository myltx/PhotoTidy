import SwiftUI
import Photos

struct CardStackView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let start = viewModel.currentIndex
            let end = min(viewModel.sessionItems.count, start + 3)
            let stackSlice = Array(viewModel.sessionItems[start..<end])

            HStack {
                Spacer()
                ZStack {
                    ForEach(Array(stackSlice.enumerated().reversed()), id: \.element.id) { localIndex, item in
                        SimpleCardWrapper(
                            item: item,
                            viewModel: viewModel,
                            dragOffset: $dragOffset,
                            isTopCard: localIndex == 0
                        )
                    }
                }
                .frame(width: min(geometry.size.width * 0.88, 420), height: geometry.size.height)
                Spacer()
            }
        }
        .onChange(of: viewModel.currentIndex) { _ in
            dragOffset = .zero
        }
    }
}

private enum SwipeDirection {
    case none, keep, delete, skip
}

private struct SimpleCardWrapper: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Binding var dragOffset: CGSize
    let isTopCard: Bool

    private var swipeDirection: SwipeDirection {
        guard isTopCard else { return .none }
        let horizontal = dragOffset.width
        let vertical = dragOffset.height
        let horizontalThreshold: CGFloat = 40
        let verticalThreshold: CGFloat = 40

        if abs(horizontal) > abs(vertical) {
            if horizontal > horizontalThreshold { return .keep }
            if horizontal < -horizontalThreshold { return .delete }
        } else if vertical < -verticalThreshold {
            return .skip
        }
        return .none
    }

    var body: some View {
        GeometryReader { geometry in
            PhotoCardView(item: item, viewModel: viewModel)
                .offset(isTopCard ? dragOffset : .zero)
                .overlay(alignment: .topTrailing) {
                    if isTopCard {
                        switch swipeDirection {
                        case .keep:
                            swipeBadge(text: "KEEP", color: .green)
                        case .delete:
                            swipeBadge(text: "DELETE", color: .red)
                        case .skip:
                            swipeBadge(text: "SKIP", color: .yellow)
                        case .none:
                            EmptyView()
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if isTopCard {
                        VStack(spacing: 4) {
                            Text("左右滑动操作，向上跳过")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                        }
                        .padding(.bottom, 18)
                    }
                }
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
        let translation = value.translation
        let width = geometry.size.width
        let height = geometry.size.height
        let horizontalThreshold = width * 0.25
        let verticalThreshold = height * 0.25

        if abs(translation.width) > abs(translation.height) {
            if translation.width > horizontalThreshold {
                viewModel.keepCurrent()
            } else if translation.width < -horizontalThreshold {
                viewModel.markCurrentForDeletion()
            }
        } else if translation.height < -verticalThreshold {
            viewModel.skipCurrent()
        }

        withAnimation(.spring()) {
            dragOffset = .zero
        }
    }

    @ViewBuilder
    private func swipeBadge(text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(UIColor.systemBackground).opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .rotationEffect(.degrees(12))
            .shadow(color: color.opacity(0.25), radius: 8, y: 4)
            .padding(.top, 18)
            .padding(.trailing, 18)
    }
}
