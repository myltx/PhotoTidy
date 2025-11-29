import Foundation
import Photos
import AVKit
import SwiftUI

struct VideoPlayerHelper: UIViewControllerRepresentable {
    let asset: PHAsset

    init(asset: PHAsset) {
        self.asset = asset
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = nil
        Task {
            let player = await context.coordinator.loadPlayer()
            await MainActor.run {
                controller.player = player
                controller.player?.play()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(asset: asset)
    }

    final class Coordinator {
        let asset: PHAsset

        init(asset: PHAsset) {
            self.asset = asset
        }

        func loadPlayer() async -> AVPlayer? {
            await withCheckedContinuation { continuation in
                let options = PHVideoRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                    if let avAsset {
                        let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
                        continuation.resume(returning: player)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
