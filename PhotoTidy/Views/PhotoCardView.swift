import SwiftUI
import Photos

struct PhotoCardView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        ZStack(alignment: .topLeading) {
            Color(UIColor.secondarySystemBackground)

            if viewModel.isZeroLatencyTimeMachineSession {
                if let image = viewModel.cachedLargeImage(for: item.id) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.9))
                        .padding(6)
                } else {
                    ZStack {
                        Color.black.opacity(0.15)
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    .padding(6)
                }
            } else {
                ZStack {
                    if let image = viewModel.cachedLargeImage(for: item.id) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(0.9))
                            .padding(6)
                    } else {
                        AssetRichPreviewView(
                            asset: item.asset,
                            contentMode: .aspectFit,
                            onRequestFullImage: { id in
                                viewModel.requestFullImage(for: id)
                            }
                        )
                        .padding(6)
                    }
                }
            }

            LinearGradient(
                colors: [.black.opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            Text(item.fileSize.fileSizeDescription)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.4))
                .clipShape(Capsule())
                .padding(16)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(cardShape)
        .overlay(cardShape.stroke(Color.white.opacity(0.9), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 8)
    }
}
