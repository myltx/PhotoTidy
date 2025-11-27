import SwiftUI
import Photos

struct PhotoCardView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        ZStack(alignment: .topLeading) {
            Color(UIColor.secondarySystemBackground)

            // 1. 底层图片（保持完整显示）
            AssetThumbnailView(
                asset: item.asset,
                imageManager: viewModel.imageManager,
                contentMode: .aspectFit
            )
            .padding(6)

            // 2. 顶部渐变，增强文字可读性
            LinearGradient(
                colors: [.black.opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            // 3. 左上角文件大小徽章
            Text(item.fileSize.fileSizeDescription)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.4))
                .clipShape(Capsule())
                .padding(16)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(cardShape) // 对 ZStack 整体进行圆角裁剪
        .overlay(cardShape.stroke(Color.white.opacity(0.9), lineWidth: 1)) // 添加描边
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 8) // 最后添加阴影
    }
}
