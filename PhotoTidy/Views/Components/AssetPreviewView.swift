import SwiftUI
import Photos
import PhotosUI

struct AssetPreviewView: View {
    let metadata: PhotoAssetMetadata
    let cornerRadius: CGFloat
    let showOverlay: Bool

    @State private var image: Image?

    init(metadata: PhotoAssetMetadata, cornerRadius: CGFloat = 24, showOverlay: Bool = true) {
        self.metadata = metadata
        self.cornerRadius = cornerRadius
        self.showOverlay = showOverlay
    }

    var body: some View {
        ZStack {
            if let image {
                image
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
        .onAppear {
            if image == nil {
                loadImage()
            }
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

    func loadImage() {
        guard let asset = metadata.resolvedAsset else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let targetSize = CGSize(width: 600, height: 600)
        manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { uiImage, _ in
            guard let uiImage else { return }
            image = Image(uiImage: uiImage)
        }
    }
}

extension PhotoAssetMetadata {
    var resolvedAsset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
}
