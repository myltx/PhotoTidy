import SwiftUI
import Photos
import PhotosUI
import UIKit

struct AssetPreviewView: View {
    let metadata: PhotoAssetMetadata
    let cornerRadius: CGFloat
    let showOverlay: Bool

    @State private var uiImage: UIImage?

    init(metadata: PhotoAssetMetadata, cornerRadius: CGFloat = 24, showOverlay: Bool = true) {
        self.metadata = metadata
        self.cornerRadius = cornerRadius
        self.showOverlay = showOverlay
    }

    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if showOverlay {
                overlayText
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear(perform: ensureLoaded)
        .onChange(of: metadata.id) { _ in
            uiImage = nil
            ensureLoaded()
        }
    }
}

private extension AssetPreviewView {
    var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(metadata.palette.gradient.opacity(0.3))
            .overlay {
                ProgressView()
            }
    }

    var overlayText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metadata.captureDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.weight(.semibold))
            Text(metadata.formattedSize)
                .font(.caption2)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding()
    }

    func ensureLoaded() {
        guard uiImage == nil else { return }
        Task {
            if let cached = await PhotoStoreFacade.shared.thumbnailImage(for: metadata) {
                await MainActor.run {
                    self.uiImage = cached
                }
            } else {
                await loadFromPhotoKit()
            }
        }
    }

    func loadFromPhotoKit() async {
        guard let asset = metadata.resolvedAsset else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 600, height: 600),
                contentMode: .aspectFill,
                options: options
            ) { uiImage, _ in
                if let uiImage {
                    Task { @MainActor in
                        self.uiImage = uiImage
                    }
                }
                continuation.resume()
            }
        }
    }
}

extension PhotoAssetMetadata {
    var resolvedAsset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
}
