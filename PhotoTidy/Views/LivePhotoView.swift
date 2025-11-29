import SwiftUI
import PhotosUI

struct LivePhotoView: UIViewRepresentable {
    let asset: PHAsset
    let isPlaying: Binding<Bool>
    let onFinished: () -> Void

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.isMuted = false
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        guard isPlaying.wrappedValue else {
            uiView.stopPlayback()
            uiView.livePhoto = nil
            return
        }
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
                uiView.isMuted = false
                uiView.startPlayback(with: .full)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: isPlaying, onFinished: onFinished)
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        let isPlaying: Binding<Bool>
        let onFinished: () -> Void

        init(isPlaying: Binding<Bool>, onFinished: @escaping () -> Void) {
            self.isPlaying = isPlaying
            self.onFinished = onFinished
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            DispatchQueue.main.async {
                self.isPlaying.wrappedValue = false
                self.onFinished()
            }
        }
    }
}
