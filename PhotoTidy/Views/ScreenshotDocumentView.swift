import SwiftUI
import Photos

struct ScreenshotDocumentView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    private var docs: [PhotoItem] {
        viewModel.items.filter { $0.isScreenshot || $0.isDocumentLike }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(docs, id: \.id) { item in
                    HStack(spacing: 16) {
                        AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                            .frame(width: 60, height: 80)
                            .cornerRadius(14)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.asset.originalFilename).font(.headline)
                            Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "未知时间")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.pendingDeletionItems.contains(where: { $0.id == item.id }) },
                            set: { flag in viewModel.setDeletion(item, to: flag) }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color("brand-start")))
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("文档 & 截图")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("全选") {
                        docs.forEach { viewModel.setDeletion($0, to: true) }
                    }
                }
            }
        }
    }
}
