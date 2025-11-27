import SwiftUI

/// 统一的模态顶部导航栏样式：左侧返回按钮 + 居中标题 + 可选右侧按钮
struct ModalNavigationHeader: View {
    let title: String
    let onClose: () -> Void
    var rightIcon: String?
    var onRightAction: (() -> Void)?

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }

            Spacer()

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            Spacer()

            if let rightIcon = rightIcon {
                Button(action: { onRightAction?() }) {
                    Image(systemName: rightIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 40, height: 40)
                }
            } else {
                Color.clear
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}
