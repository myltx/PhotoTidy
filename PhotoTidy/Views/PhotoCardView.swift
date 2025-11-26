import SwiftUI
import Photos

struct PhotoCardView: View {
    let item: PhotoItem
    @ObservedObject var viewModel: PhotoCleanupViewModel

    var body: some View {
        AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
            .aspectRatio(1, contentMode: .fill)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(24)
            .clipped()
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 8)
            .overlay(
                ZStack(alignment: .topLeading) {
                    // Transparent gradient at the top for better text visibility
                    LinearGradient(
                        colors: [.black.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    
                    // File size badge
                    Text(item.fileSize.fileSizeDescription)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())
                        .padding(16)
                }
                , alignment: .top
            )
    }
}
