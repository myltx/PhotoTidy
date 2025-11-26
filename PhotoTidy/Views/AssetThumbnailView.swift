
import SwiftUI
import Photos
import UIKit

struct AssetThumbnailView: View {
    let asset: PHAsset
    let imageManager: PHCachingImageManager
    var contentMode: PHImageContentMode = .aspectFill

    @State private var uiImage: UIImage?

    var body: some View {
        Color.clear
            .overlay(
                Group {
                    if let image = uiImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                ProgressView().scaleEffect(0.8)
                            )
                    }
                }
            )
            .clipped()
            .onAppear {
                request()
            }
        // 当绑定的 PHAsset 发生变化时，重置并重新请求缩略图，
        // 避免 SwiftUI 复用旧的 @State 导致图片看起来没变。
        .onChange(of: asset.localIdentifier) { _ in
            uiImage = nil
            request()
        }
    }

    private func request() {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let scale = UIScreen.main.scale
        let size = CGSize(width: 200 * scale, height: 200 * scale)

        imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: contentMode,
            options: options
        ) { image, _ in
            if let img = image {
                self.uiImage = img
            }
        }
    }
}
