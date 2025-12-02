
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
            // 背景黑色区域，点击空白处可关闭
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack {
                Spacer()
                AssetThumbnailView(
                    asset: item.asset,
                    target: .detailFit
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
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 32, height: 32)
                        .padding()
                    }
                    Spacer()
                }
                Spacer()
            }
        }
    }
}
