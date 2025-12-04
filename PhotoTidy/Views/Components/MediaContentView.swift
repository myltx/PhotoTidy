import SwiftUI
import Photos
import PhotosUI
import AVKit
import WebKit
import UniformTypeIdentifiers

struct MediaContentView: View {
    let metadata: PhotoAssetMetadata

    @State private var livePhoto: PHLivePhoto?
    @State private var livePlayTrigger = 0
    @State private var queuePlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var gifData: Data?

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .onAppear { loadMediaIfNeeded() }
            .onChange(of: metadata.id) { _ in resetCaches(); loadMediaIfNeeded() }
    }
}

private extension MediaContentView {
    @ViewBuilder
    var content: some View {
        switch metadata.mediaType {
        case .photo:
            AssetPreviewView(metadata: metadata, cornerRadius: 32, showOverlay: false)
        case .live:
            if let livePhoto {
                LivePhotoPlayerView(livePhoto: livePhoto, playTrigger: livePlayTrigger)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        livePlayTrigger += 1
                    }
            } else {
                placeholder
            }
        case .video:
            if let queuePlayer {
                VideoPlayer(player: queuePlayer)
                    .onAppear {
                        queuePlayer.isMuted = true
                        queuePlayer.play()
                    }
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
        AssetPreviewView(metadata: metadata, cornerRadius: 32, showOverlay: false)
            .overlay {
                ProgressView()
            }
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
        livePhoto = nil
        queuePlayer = nil
        playerLooper = nil
        gifData = nil
    }

    func loadLivePhoto(asset: PHAsset) {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestLivePhoto(for: asset, targetSize: CGSize(width: 1600, height: 1600), contentMode: .aspectFill, options: options) { livePhoto, _ in
            DispatchQueue.main.async {
                self.livePhoto = livePhoto
            }
        }
    }

    func loadVideo(asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let avAsset else { return }
            let playerItem = AVPlayerItem(asset: avAsset)
            let queuePlayer = AVQueuePlayer()
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            DispatchQueue.main.async {
                self.queuePlayer = queuePlayer
                self.playerLooper = looper
                queuePlayer.play()
            }
        }
    }

    func loadGIF(asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
            guard let data else { return }
            if let uti,
               let type = UTType(uti),
               type.conforms(to: .gif) {
                DispatchQueue.main.async {
                    self.gifData = data
                }
            } else {
                DispatchQueue.main.async {
                    self.gifData = data
                }
            }
        }
    }
}

private struct LivePhotoPlayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playTrigger: Int

    func makeUIView(context: Context) -> PHLivePhotoView {
        PHLivePhotoView()
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
        if context.coordinator.playCounter != playTrigger {
            uiView.startPlayback(with: .full)
            context.coordinator.playCounter = playTrigger
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var playCounter: Int = 0
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
