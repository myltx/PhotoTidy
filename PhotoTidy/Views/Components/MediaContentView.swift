import SwiftUI
import Photos
import PhotosUI
import AVKit
import WebKit
import UniformTypeIdentifiers

struct MediaContentView: View {
    let metadata: PhotoAssetMetadata

    @State private var livePhoto: PHLivePhoto?
    @State private var avPlayer: AVPlayer?
    @State private var gifData: Data?
    @State private var liveRequestID: PHImageRequestID?
    @State private var videoRequestID: PHImageRequestID?
    @State private var gifRequestID: PHImageRequestID?

    var body: some View {
        GeometryReader { proxy in
            let size = targetSize(for: proxy.size)
            ZStack {
                Color.clear
                mediaSurface
                    .frame(width: size.width, height: size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { loadMediaIfNeeded() }
            .onDisappear { cancelOngoingRequests() }
            .onChange(of: metadata.id) { _ in resetCaches(); loadMediaIfNeeded() }
        }
        .frame(height: 600)
    }
}

private extension MediaContentView {
    var mediaSurface: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(alignment: .center) {
                if isWaitingForStageThree {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    var content: some View {
        switch metadata.mediaType {
        case .photo:
            AssetPreviewView(metadata: metadata, cornerRadius: 32, showOverlay: false, contentMode: .fit)
        case .live:
            if let livePhoto {
                LivePhotoPlayerView(livePhoto: livePhoto)
            } else {
                placeholder
            }
        case .video:
            if let avPlayer {
                PhotosVideoPlayerView(player: avPlayer)
            } else {
                placeholder
            }
        case .gif:
            if let gifData {
                GIFPlayerView(data: gifData)
            } else {
                placeholder
            }
        }
    }

    var placeholder: some View {
        AssetPreviewView(metadata: metadata, cornerRadius: 32, showOverlay: false, contentMode: .fit)
    }

    func loadMediaIfNeeded() {
        guard let asset = metadata.resolvedAsset else { return }
        switch metadata.mediaType {
        case .live:
            loadLivePhoto(asset: asset)
        case .video:
            loadVideo(asset: asset)
        case .gif:
            loadGIF(asset: asset)
        case .photo:
            break
        }
    }

    func resetCaches() {
        cancelOngoingRequests()
        livePhoto = nil
        avPlayer = nil
        gifData = nil
    }

    func loadLivePhoto(asset: PHAsset) {
        cancelLivePhotoRequest()
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let requestID = PHImageManager.default().requestLivePhoto(
            for: asset,
            targetSize: CGSize(width: 1600, height: 1600),
            contentMode: .aspectFill,
            options: options
        ) { livePhoto, _ in
            DispatchQueue.main.async {
                self.livePhoto = livePhoto
                self.liveRequestID = nil
            }
        }
        liveRequestID = requestID
    }

    func loadVideo(asset: PHAsset) {
        cancelVideoRequest()
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let requestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            DispatchQueue.main.async {
                if let playerItem {
                    let player = AVPlayer(playerItem: playerItem)
                    player.actionAtItemEnd = .pause
                    player.allowsExternalPlayback = false
                    self.avPlayer = player
                } else {
                    self.avPlayer = nil
                }
                self.videoRequestID = nil
            }
        }
        videoRequestID = requestID
    }

    func loadGIF(asset: PHAsset) {
        cancelGIFRequest()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let requestID = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
            DispatchQueue.main.async {
                defer { self.gifRequestID = nil }
                guard let data else {
                    self.gifData = nil
                    return
                }
                if let uti,
                   let type = UTType(uti),
                   type.conforms(to: .gif) {
                    self.gifData = data
                } else {
                    self.gifData = data
                }
            }
        }
        gifRequestID = requestID
    }

    var isWaitingForStageThree: Bool {
        switch metadata.mediaType {
        case .live:
            return livePhoto == nil && liveRequestID != nil
        case .video:
            return avPlayer == nil && videoRequestID != nil
        case .gif:
            return gifData == nil && gifRequestID != nil
        case .photo:
            return false
        }
    }

    func cancelOngoingRequests() {
        cancelLivePhotoRequest()
        cancelVideoRequest()
        cancelGIFRequest()
    }

    func cancelLivePhotoRequest() {
        if let id = liveRequestID {
            PHImageManager.default().cancelImageRequest(id)
            liveRequestID = nil
        }
    }

    func cancelVideoRequest() {
        if let id = videoRequestID {
            PHImageManager.default().cancelImageRequest(id)
            videoRequestID = nil
        }
    }

    func cancelGIFRequest() {
        if let id = gifRequestID {
            PHImageManager.default().cancelImageRequest(id)
            gifRequestID = nil
        }
    }

    func targetSize(for container: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 10 // 左右各 5pt
        let verticalPadding: CGFloat = 0
        let maxWidth = max(container.width - horizontalPadding, 0)
        let maxHeight = max(container.height - verticalPadding, 0)
        let aspect = max(CGFloat(metadata.aspectRatio), 0.1)
        var width = maxWidth
        var height = width / aspect
        if height > maxHeight, maxHeight > 0 {
            height = maxHeight
            width = height * aspect
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }
}

private struct LivePhotoPlayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.isMuted = false
        view.isUserInteractionEnabled = true
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.08
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)
        context.coordinator.photoView = view
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var photoView: PHLivePhotoView?

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = photoView else { return }
            switch gesture.state {
            case .began:
                view.startPlayback(with: .full)
            case .ended, .cancelled, .failed:
                view.stopPlayback()
            default:
                break
            }
        }
    }
}

private struct PhotosVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
            controller.player?.play()
        }
    }
}

private struct GIFPlayerView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.load(data, mimeType: "image/gif", characterEncodingName: "utf-8", baseURL: URL(fileURLWithPath: ""))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(data, mimeType: "image/gif", characterEncodingName: "utf-8", baseURL: URL(fileURLWithPath: ""))
    }
}

private struct MediaTypeBadge: View {
    let type: PhotoAssetMetadata.MediaType

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.7), lineWidth: 0.5)
            )
            .foregroundColor(.white)
    }

    private var text: String {
        switch type {
        case .photo: return "PHOTO"
        case .live: return "LIVE"
        case .video: return "VIDEO"
        case .gif: return "GIF"
        }
    }
}
