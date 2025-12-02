import SwiftUI
import Photos
import PhotosUI
import AVKit
import ImageIO

/// 展示照片/视频/实况/动图的富预览视图，用于清理器等需要直接操作原资源的场景。
struct AssetRichPreviewView: View {
    let asset: PHAsset
    var contentMode: PHImageContentMode = .aspectFit

    @State private var player: AVPlayer?
    @State private var playerObserver: NSObjectProtocol?
    @State private var isVideoPlaying = false
    @State private var isLivePhotoPlaying = false
    @State private var animatedImage: UIImage?
    @State private var animatedDuration: Double = 0
    @State private var isAnimatedPlaying = false
    @State private var isPreparingVideo = false

    private var badgeStyle: PlaybackBadge.Style? {
        switch asset.playbackStyle {
        case .video, .videoLooping:
            return nil
        case .livePhoto:
            return .livePhoto
        default:
            return nil
        }
    }

    private var requiresPlayButton: Bool {
        badgeStyle != nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            previewView
            if let badgeStyle = badgeStyle, !isPlaybackActive {
                PlaybackBadge(style: badgeStyle)
                    .padding(12)
                    .onTapGesture { startPlayback() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onDisappear {
            player?.pause()
            isVideoPlaying = false
            isLivePhotoPlaying = false
            isAnimatedPlaying = false
        }
        .task(id: asset.localIdentifier) {
            if asset.playbackStyle == .imageAnimated {
                await autoPlayAnimatedImage()
            }
            if asset.playbackStyle == .video || asset.playbackStyle == .videoLooping {
                prepareVideoIfNeeded()
            }
        }
    }

    private var isPlaybackActive: Bool {
        switch asset.playbackStyle {
        case .video, .videoLooping:
            return isVideoPlaying
        case .livePhoto:
            return isLivePhotoPlaying
        case .imageAnimated:
            return isAnimatedPlaying
        default:
            return false
        }
    }

    @ViewBuilder
    private var previewView: some View {
        switch asset.playbackStyle {
        case .video, .videoLooping:
            ZStack {
                if let player {
                    VStack {
                        Spacer()
                        VideoPlayer(player: player)
                            .frame(height: 260)
                            .background(Color.black.opacity(0.6))
                            .onAppear {
                                player.pause()
                                player.seek(to: .zero)
                                player.isMuted = true
                            }
                        Spacer()
                    }
                } else {
                    AssetThumbnailView(asset: asset, target: .detailFit)
                        .frame(height: 260)
                }
            }
        case .livePhoto:
            ZStack {
                AssetThumbnailView(asset: asset, target: .detailFit)
                    .opacity(isLivePhotoPlaying ? 0 : 1)
                if isLivePhotoPlaying {
                    LivePhotoPlayerView(asset: asset, isPlaying: $isLivePhotoPlaying)
                }
            }
        case .imageAnimated:
            if let animatedImage, isAnimatedPlaying {
                Image(uiImage: animatedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.black.opacity(0.05))
            } else {
                AssetThumbnailView(asset: asset, target: .detailFit)
            }
        default:
            AssetThumbnailView(asset: asset, target: .detailFit)
        }
    }

    private func startPlayback() {
        switch asset.playbackStyle {
        case .video, .videoLooping:
            Task {
                if player == nil {
                    player = await loadPlayer()
                }
                await MainActor.run {
                    preparePlayerObserver()
                    isVideoPlaying = player != nil
                    player?.seek(to: .zero)
                    player?.isMuted = true
                    player?.play()
                }
            }
        case .livePhoto:
            isLivePhotoPlaying = true
        case .imageAnimated:
            Task {
                if animatedImage == nil {
                    if let payload = await loadAnimatedImage() {
                        await MainActor.run {
                            animatedImage = payload.image
                            animatedDuration = payload.duration
                            playAnimatedImage()
                        }
                    }
                } else {
                    playAnimatedImage()
                }
            }
        default:
            break
        }
    }

    private func playAnimatedImage() {
        guard animatedImage != nil else { return }
        isAnimatedPlaying = true
        let duration = animatedDuration > 0 ? animatedDuration : (animatedImage?.duration ?? 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            isAnimatedPlaying = false
        }
    }

    private func autoPlayAnimatedImage() async {
        if animatedImage == nil {
            if let payload = await loadAnimatedImage() {
                await MainActor.run {
                    animatedImage = payload.image
                    animatedDuration = payload.duration
                }
            }
        }
        await MainActor.run {
            playAnimatedImage()
        }
    }

    private func prepareVideoIfNeeded() {
        guard asset.playbackStyle == .video || asset.playbackStyle == .videoLooping else { return }
        if player != nil || isPreparingVideo { return }
        isPreparingVideo = true
        Task {
            let loaded = await loadPlayer()
            await MainActor.run {
                player = loaded
                player?.isMuted = true
                player?.pause()
                player?.seek(to: .zero)
                isPreparingVideo = false
            }
        }
    }

    private func preparePlayerObserver() {
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        guard let item = player?.currentItem else { return }
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isVideoPlaying = false
            player?.seek(to: .zero)
        }
    }

    private func loadPlayer() async -> AVPlayer? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .mediumQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let avAsset {
                    let item = AVPlayerItem(asset: avAsset)
                    continuation.resume(returning: AVPlayer(playerItem: item))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadAnimatedImage() async -> (image: UIImage, duration: Double)? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .original
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if let data, let result = UIImage.animatedImageWithDuration(data: data) {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private struct PlaybackBadge: View {
    enum Style {
        case livePhoto
        case video
    }

    let style: Style

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())
    }

    private var systemImage: String {
        switch style {
        case .livePhoto:
            if #available(iOS 15.0, *) {
                return "livephoto.play"
            } else {
                return "livephoto"
            }
        case .video:
            return "play.fill"
        }
    }
}

// MARK: - Live Photo

private struct LivePhotoPlayerView: UIViewRepresentable {
    let asset: PHAsset
    @Binding var isPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying)
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.delegate = context.coordinator
        if isPlaying {
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, _ in
                uiView.livePhoto = livePhoto
                if let livePhoto {
                    uiView.startPlayback(with: .hint)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        uiView.startPlayback(with: .full)
                    }
                }
            }
        } else {
            uiView.stopPlayback()
            uiView.livePhoto = nil
        }
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        private var isPlaying: Binding<Bool>
        init(isPlaying: Binding<Bool>) {
            self.isPlaying = isPlaying
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            DispatchQueue.main.async {
                self.isPlaying.wrappedValue = false
            }
        }
    }
}

// MARK: - Helpers

private extension UIImage {
    static func animatedImageWithDuration(data: Data) -> (image: UIImage, duration: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            if let image = UIImage(data: data) { return (image, 0) }
            return nil
        }

        var images: [UIImage] = []
        var duration: Double = 0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let frameDuration = frameDelay(at: index, source: source)
            duration += frameDuration
            images.append(UIImage(cgImage: cgImage))
        }
        if duration == 0 { duration = Double(count) * 0.1 }
        if let animated = UIImage.animatedImage(with: images, duration: duration) {
            return (animated, duration)
        }
        return nil
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
