import SwiftUI

/// 启动阶段的加载动画视图，复刻设计稿中的「Phone Mockup + 渐变图标」效果。
struct SplashLoadingView: View {
    @State private var iconOffset: CGFloat = 12
    @State private var textPulseOpacity: Double = 0.6

    private let backgroundColor = Color(red: 243/255, green: 244/255, blue: 246/255)

    var body: some View {
        GeometryReader { proxy in
            let phoneWidth = min(proxy.size.width - 48, 360)
            let phoneHeight = min(proxy.size.height - 140, 720)

            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 52, style: .continuous)
                    .fill(Color.white)
                    .frame(width: phoneWidth, height: phoneHeight)
                    .shadow(color: .black.opacity(0.15), radius: 25, y: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 52, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                VStack(spacing: 24) {
                    Spacer(minLength: phoneHeight * 0.15)

                    iconStack
                        .offset(y: iconOffset)

                    VStack(spacing: 10) {
                        Text("PhotoTidy")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundColor(Color("brand-start"))
                            .tracking(1)
                            .shadow(color: Color("brand-start").opacity(0.25), radius: 8, y: 4)

                        Text("让回忆整洁如新")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                            .tracking(4)
                            .opacity(textPulseOpacity)
                    }

                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(Color("brand-start"))
                        Text("正在加载您的相册…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)

                    Spacer()

                    Text("Designed for simplicity.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.bottom, 32)
                }
                .frame(width: phoneWidth * 0.8)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    iconOffset = -12
                }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    textPulseOpacity = 1
                }
            }
        }
    }

    private var iconStack: some View {
        Image("app_logo")
            .resizable()
            .scaledToFit()
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 18, y: 10)
    }
}
