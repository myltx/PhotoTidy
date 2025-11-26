import SwiftUI
import Photos

struct LargeFilesView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    private var largeItems: [PhotoItem] {
        viewModel.items.filter { $0.isLargeFile }.sorted { $0.fileSize > $1.fileSize }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(largeItems, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                            .frame(height: 180)
                            .cornerRadius(16)
                            .overlay(alignment: .topTrailing) {
                                Text(item.fileSize.fileSizeDescription)
                                    .font(.caption).bold()
                                    .padding(8)
                                    .background(.regularMaterial)
                                    .clipShape(Capsule())
                                    .padding(10)
                            }
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.asset.originalFilename).font(.headline)
                                Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                let isDeleted = viewModel.pendingDeletionItems.contains(where: { $0.id == item.id })
                                viewModel.setDeletion(item, to: !isDeleted)
                            } label: {
                                Text(viewModel.pendingDeletionItems.contains(where: { $0.id == item.id }) ? "已加入待删" : "加入待删")
                                    .font(.caption).bold()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color("brand-start").opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.plain)
            .navigationTitle("大文件清理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
