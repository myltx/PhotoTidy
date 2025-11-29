import SwiftUI
import Photos
import AVKit

struct PhotoCardView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showVideoPlayer = false
    @State private var playLivePhoto = false

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        ZStack(alignment: .topLeading) {
            Color(UIColor.secondarySystemBackground)

            cardContent
                .padding(6)

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
        .sheet(isPresented: $showVideoPlayer) {
            VideoPlayerHelper(asset: item.asset)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        let kind = assetType(item.asset)
        switch kind {
        case .staticPhoto:
            AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFit)
        case .gif:
            AnimatedImageView(asset: item.asset)
        case .livePhoto:
            ZStack(alignment: .bottomLeading) {
                AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFit)
                if playLivePhoto {
                    LivePhotoView(asset: item.asset, isPlaying: $playLivePhoto) {
                        playLivePhoto = false
                    }
                }
                CardPlayBadge(style: .livePhoto)
                    .padding(12)
                    .onTapGesture { playLivePhoto = true }
            }
        case .video:
            ZStack(alignment: .bottomLeading) {
                AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFit)
                CardPlayBadge(style: .video)
                    .padding(12)
                    .onTapGesture { showVideoPlayer = true }
            }
        }
    }
}

private struct CardPlayBadge: View {
    enum Style {
        case livePhoto
        case video
    }

    let style: Style

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImageName)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }

    private var systemImageName: String {
        switch style {
        case .livePhoto:
            if #available(iOS 15.0, *) {
                return "livephoto.play"
            } else {
                return "livephoto"
            }
        case .video:
            return "play.fill"
        }
    }
}
