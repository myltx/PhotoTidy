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
                // 先渲染更靠后的卡片，再渲染当前卡片，保证当前卡片始终在最上层
                ForEach(Array(stackSlice.enumerated().reversed()), id: \.element.id) { localIndex, item in
                    // 此处 localIndex 即「距离当前卡片的偏移」：0 = 当前、1 = 下一张、2 = 第三张
                    let indexInStack = localIndex
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

private enum SwipeDirection {
    case none, keep, delete, skip
}

private struct PhotoCardViewWrapper: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Binding var dragOffset: CGSize

    let indexInStack: Int // 0 = top card

    private var isTopCard: Bool { indexInStack == 0 }

    // 堆叠层次感：越靠下的卡片越小、越往下偏移
    private var scale: CGFloat { 1.0 - (CGFloat(indexInStack) * 0.06) }
    private var yOffset: CGFloat { CGFloat(indexInStack) * 18 }

    // 轻微基础旋转，让卡片看起来更有层次
    private var baseRotation: Double {
        switch indexInStack {
        case 0: return 1.0
        case 1: return -3.0
        default: return -5.0
        }
    }

    private var cardRotation: Angle {
        if isTopCard {
            return .degrees(baseRotation + Double(dragOffset.width / 25))
        } else {
            return .degrees(baseRotation)
        }
    }

    private var cardOpacity: Double {
        indexInStack == 0 ? 1.0 : max(0.7, 1.0 - Double(indexInStack) * 0.15)
    }

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
                .scaleEffect(isTopCard ? 1.0 : scale)
                .offset(y: isTopCard ? 0 : yOffset)
                .offset(isTopCard ? dragOffset : .zero)
                .rotationEffect(cardRotation)
                .opacity(cardOpacity)
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
                            Text("上滑跳过")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                            Image(systemName: "chevron.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                        }
                        .padding(.bottom, 18)
                    }
                }
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
        let translation = value.translation
        let width = geometry.size.width
        let height = geometry.size.height

        let horizontalThreshold = width * 0.25
        let verticalThreshold = height * 0.25

        if abs(translation.width) > abs(translation.height) {
            if translation.width > horizontalThreshold {
            // 右滑：保留
                viewModel.keepCurrent()
            } else if translation.width < -horizontalThreshold {
                // 左滑：加入待删区
                viewModel.markCurrentForDeletion()
            }
        } else if translation.height < -verticalThreshold {
            // 上滑：跳过
            viewModel.moveToNext()
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
