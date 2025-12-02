
import SwiftUI
import Photos
import UIKit

/// 统一的缩略图视图，优先使用 ThumbnailStore，必要时回退到 PhotoKit
struct AssetThumbnailView: View {
    let asset: PHAsset
    var target: ThumbnailTarget

    @State private var uiImage: UIImage?
    @State private var loadTask: Task<Void, Never>?

    init(asset: PHAsset, target: ThumbnailTarget = .dashboardCard) {
        self.asset = asset
        self.target = target
    }

    var body: some View {
        Color.clear
            .overlay(
                Group {
                    if let image = uiImage {
                        if target.contentMode == .aspectFill {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.18))
                            .overlay(
                                ProgressView().scaleEffect(0.7)
                            )
                    }
                }
            )
            .onAppear {
                loadThumbnail()
            }
            .onDisappear {
                loadTask?.cancel()
            }
            .onChange(of: asset.localIdentifier) { _ in
                uiImage = nil
                loadThumbnail()
            }
    }

    private func loadThumbnail() {
        loadTask?.cancel()
        loadTask = Task {
            if let image = await PhotoCleanupViewModel.shared?.thumbnail(for: asset.localIdentifier, target: target) {
                guard !Task.isCancelled else { return }
                await MainActor.run { self.uiImage = image }
                return
            }
            guard !Task.isCancelled else { return }
            if let fallback = await fallbackThumbnail() {
                guard !Task.isCancelled else { return }
                await MainActor.run { self.uiImage = fallback }
            }
        }
    }

    private func fallbackThumbnail() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            var resumed = false

            PHCachingImageManager().requestImage(
                for: asset,
                targetSize: target.pixelSize,
                contentMode: target.contentMode,
                options: options
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
