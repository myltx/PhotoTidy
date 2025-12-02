
import SwiftUI
import Photos

/// 简单的网格浏览视图：一次性列出所有资源，方便整体浏览和批量选择。
struct AlbumGridView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        NavigationView {
            Group {
                if viewModel.items.isEmpty {
                    VStack(spacing: 12) {
                        Text("相册中暂无可显示的照片")
                            .foregroundColor(.secondary)
                        if viewModel.authorizationStatus == .limited {
                            Text("当前为“限制访问”，可以在系统设置中为本应用选择更多照片。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(viewModel.items) { item in
                                AssetThumbnailView(
                                    asset: item.asset,
                                    target: .smallGrid
                                )
                                .aspectRatio(1, contentMode: .fit)
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle("相册 (\(viewModel.items.count))")
        }
    }
}
