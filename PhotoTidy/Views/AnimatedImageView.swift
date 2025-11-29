import SwiftUI
import Photos
import ImageIO

struct AnimatedImageView: View {
    let asset: PHAsset
    @State private var animatedImage: UIImage?

    var body: some View {
        Group {
            if let animatedImage {
                Image(uiImage: animatedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.black.opacity(0.05)
                ProgressView()
            }
        }
        .task(id: asset.localIdentifier) {
            animatedImage = await loadAnimatedImage()
        }
    }

    private func loadAnimatedImage() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .original
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if let data {
                    continuation.resume(returning: UIImage.animatedImage(withGIFData: data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private extension UIImage {
    static func animatedImage(withGIFData data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }

        var images: [UIImage] = []
        var duration: Double = 0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let frameDuration = frameDelay(at: index, source: source)
            duration += frameDuration
            images.append(UIImage(cgImage: cgImage))
        }
        if duration == 0 { duration = Double(count) * 0.1 }
        return UIImage.animatedImage(with: images, duration: duration)
    }

    private static func frameDelay(at index: Int, source: CGImageSource) -> Double {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }
        if let delay = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, delay > 0 {
            return delay
        }
        if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
            return delay
        }
        return 0.1
    }
}
