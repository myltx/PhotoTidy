
import SwiftUI
import Photos

struct FullScreenPreviewView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer()
                AssetThumbnailView(
                    asset: item.asset,
                    imageManager: viewModel.imageManager,
                    contentMode: .aspectFit
                )
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 1.0), 4.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
                Spacer()

                VStack(spacing: 6) {
                    if let date = item.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.white)
                            .font(.footnote)
                    }
                    Text(
                        "\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height)) · \(item.fileSize.fileSizeDescription)"
                    )
                    .foregroundColor(.white.opacity(0.7))
                    .font(.footnote)
                }
                .padding(.bottom, 20)
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding()
                    }
                    Spacer()
                }
                Spacer()
            }
        }
    }
}
