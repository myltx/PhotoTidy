import SwiftUI

struct TrashView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingClearAllAlert = false
    @State private var showingConfirmAlert = false
    @State private var selection: Set<String> = []

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if items.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(items) { item in
                                TrashPreviewCell(
                                    item: item,
                                    isSelected: selection.contains(item.id),
                                    onToggle: { toggleSelection(for: item.id) },
                                    onRestore: { viewModel.removeAssetFromPending(id: item.id) }
                                )
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selection)
                            }
                        }
                        .padding(.top, 46)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("待删区")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.systemBackground))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingClearAllAlert = true
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(items.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            selectionBar
        }
        .alert("清空待删区？", isPresented: $showingClearAllAlert) {
            Button("取消", role: .cancel) {}
            Button("确定清空", role: .destructive) {
                viewModel.clearPendingDeletionCache()
            }
        } message: {
            Text("将移除所有照片的待删标记，可在首页或时间轴重新选择。")
        }
        .alert("确认删除这些照片？", isPresented: $showingConfirmAlert) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                viewModel.confirmPendingDeletion(ids: Array(selection))
                selection.removeAll()
            }
        } message: {
            Text("这些照片将从 PhotoTidy 数据集中移除，请在系统“最近删除”中完成最终删除。")
        }
        .onAppear(perform: syncSelectionWithItems)
        .onChange(of: viewModel.pendingDeletionItems) { _ in
            syncSelectionWithItems()
        }
    }
}

private extension TrashView {
    var items: [PhotoAssetMetadata] {
        viewModel.pendingDeletionItems.sorted { $0.captureDate > $1.captureDate }
    }

    var totalSizeText: String {
        viewModel.pendingDeletionTotalSize.fileSizeDescription
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 46))
                .foregroundColor(.secondary)
            Text("待删区为空")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    var selectionBar: some View {
        if items.isEmpty {
            return AnyView(Color.clear.frame(height: 0))
        }
        return AnyView(
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.isEmpty ? "请选择需要删除的照片" : "已选择 \(selection.count) 项")
                        .font(.system(size: 13, weight: .semibold))
                    Text("总计 \(selectedSizeText)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    selectAll()
                } label: {
                    Text(selection.count == items.count ? "取消全选" : "全选")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(Capsule())
                }

                Button {
                    showingConfirmAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("确认删除")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color("brand-start"))
                    .clipShape(Capsule())
                }
                .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)
            .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        )
    }

    var selectedSizeText: String {
        let selectedItems = items.filter { selection.contains($0.id) }
        let totalBytes = selectedItems.reduce(0) { $0 + $1.byteSize }
        return totalBytes.fileSizeDescription
    }

    func syncSelectionWithItems() {
        let ids = Set(items.map(\.id))
        if selection.isEmpty || !selection.isSubset(of: ids) {
            selection = ids
        } else {
            selection = selection.intersection(ids)
        }
    }

    func toggleSelection(for id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func selectAll() {
        if selection.count == items.count {
            selection.removeAll()
        } else {
            selection = Set(items.map(\.id))
        }
    }
}

private struct TrashPreviewCell: View {
    let item: PhotoAssetMetadata
    let isSelected: Bool
    let onToggle: () -> Void
    let onRestore: () -> Void

    var body: some View {
        ZStack {
            AssetPreviewView(metadata: item, cornerRadius: 16, showOverlay: false, contentMode: .fit)
                .frame(height: 120)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .onTapGesture(perform: onToggle)

            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.accentColor)
                    .padding(6)
                    .background(Color(UIColor.systemBackground), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
