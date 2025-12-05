import SwiftUI
import AVKit
import Photos

struct CarouselReviewView: View {
    @StateObject private var viewModel = PhotoFeedViewModel(intent: .sequential(scope: .all))
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var lastAction: CardAction?
    @State private var showActionFeedback = false
    @State private var selectedAlbum: String = "全部"

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let metadata = currentMetadata {
                    Text(metadata.fileName)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                    AlbumFilterView(selectedAlbum: $selectedAlbum, albums: availableAlbums)
                    MediaCard(metadata: metadata, dragOffset: $dragOffset, pendingAction: pendingAction)
                        .gesture(cardGesture(for: metadata))
                        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: dragOffset)
                        .overlay(alignment: .top) {
                            if showActionFeedback, let lastAction {
                                ActionFeedbackView(action: lastAction)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity, alignment: .center)
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .onChange(of: assetItems.count) { _ in
                clampIndex()
            }
            .onChange(of: effectiveAlbumFilter) { _ in
                currentIndex = 0
                clampIndex()
            }
        }
    }
}

private extension CarouselReviewView {
    var emptyState: some View {
        VStack(spacing: 12) {
            ProgressView("正在加载照片…")
                .progressViewStyle(.circular)
            Text("正在准备滑动任务，请稍候")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    func cardGesture(for metadata: PhotoAssetMetadata) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let translation = value.translation
                if abs(translation.height) > abs(translation.width),
                   translation.height < -80 {
                    handleAction(.skip, metadata: metadata)
                } else if translation.width < -80 {
                    handleAction(.delete, metadata: metadata)
                } else if translation.width > 80 {
                    handleAction(.keep, metadata: metadata)
                } else {
                    withAnimation {
                        dragOffset = .zero
                    }
                }
            }
    }

    func handleAction(_ action: CardAction, metadata: PhotoAssetMetadata) {
        commitDecision(for: metadata, action: action)
        lastAction = action
        withAnimation {
            showActionFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation {
                showActionFeedback = false
            }
        }
        advanceToNextItem()
    }

    func commitDecision(for metadata: PhotoAssetMetadata, action: CardAction) {
        let id = metadata.id
        switch action {
        case .skip:
            PhotoStoreFacade.shared.applyDecision(assetIds: [id], newState: .skipped)
        case .delete:
            PhotoStoreFacade.shared.applyDecision(assetIds: [id], newState: .pendingDeletion)
        case .keep:
            PhotoStoreFacade.shared.applyDecision(assetIds: [id], newState: .clean)
        }
    }

    func advanceToNextItem() {
        withAnimation {
            dragOffset = .zero
        }
        currentIndex += 1
        if currentIndex >= max(0, assetItems.count - 3) {
            viewModel.requestNextPage()
        }
        clampIndex()
    }

    func clampIndex() {
        let count = filteredItems.count
        if count == 0 {
            currentIndex = 0
        } else if currentIndex >= count {
            currentIndex = count - 1
        }
    }

    var assetItems: [PhotoFeedItem] {
        viewModel.state.items.filter {
            if case .asset = $0.payload { return true }
            return false
        }
    }

    var availableAlbums: [String] {
        let names = assetItems.compactMap { item -> String? in
            if case let .asset(asset) = item.payload {
                return asset.albumName
            }
            return nil
        }
        let unique = Set(names)
        return ["全部"] + unique.sorted()
    }

    var effectiveAlbumFilter: String {
        availableAlbums.contains(selectedAlbum) ? selectedAlbum : "全部"
    }

    var filteredItems: [PhotoFeedItem] {
        guard effectiveAlbumFilter != "全部" else { return assetItems }
        return assetItems.filter { item in
            guard case let .asset(asset) = item.payload else { return false }
            return asset.albumName == effectiveAlbumFilter
        }
    }

    var currentItem: PhotoFeedItem? {
        guard currentIndex >= 0, currentIndex < filteredItems.count else { return nil }
        return filteredItems[currentIndex]
    }

    var currentMetadata: PhotoAssetMetadata? {
        guard let item = currentItem else { return nil }
        if case let .asset(asset) = item.payload {
            return asset
        }
        return nil
    }

    var pendingAction: CardAction? {
        let translation = dragOffset
        if abs(translation.height) > abs(translation.width) && translation.height < -40 {
            return .skip
        } else if translation.width < -40 {
            return .delete
        } else if translation.width > 40 {
            return .keep
        }
        return nil
    }
}

private enum CardAction {
    case skip
    case delete
    case keep

    var title: String {
        switch self {
        case .skip: return "跳过"
        case .delete: return "加入待删区"
        case .keep: return "保留"
        }
    }

    var color: Color {
        switch self {
        case .skip: return .gray
        case .delete: return .red
        case .keep: return .green
        }
    }

    var icon: String {
        switch self {
        case .skip: return "arrow.up"
        case .delete: return "trash"
        case .keep: return "checkmark"
        }
    }
}

private struct MediaCard: View {
    let metadata: PhotoAssetMetadata
    @Binding var dragOffset: CGSize
    var pendingAction: CardAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MediaContentView(metadata: metadata)
                .frame(height: 600)
                .overlay(alignment: .bottom) {
                    HStack {
                        Text(metadata.formattedDate)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        Text(metadata.formattedSize)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding()
                }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                MediaTypeBadge(type: metadata.mediaType)
                if let pendingAction, pendingAction == .keep {
                    ActionIndicatorView(action: pendingAction)
                }
            }
            .padding()
        }
        .overlay(alignment: .topTrailing) {
            if let pendingAction, pendingAction != .keep {
                ActionIndicatorView(action: pendingAction)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .offset(dragOffset)
        .rotationEffect(.degrees(Double(dragOffset.width / 20)))
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

private struct ActionFeedbackView: View {
    let action: CardAction

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: action.icon)
            Text(action.title)
                .bold()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(action.color.opacity(0.8), in: Capsule())
        .foregroundColor(.white)
        .padding()
    }
}

private struct ActionIndicatorView: View {
    let action: CardAction

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: action.icon)
            Text(action.title)
        }
        .font(.caption.bold())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(action.color.opacity(0.85), in: Capsule())
        .foregroundColor(.white)
    }
}

private struct MediaTypeBadge: View {
    let type: PhotoAssetMetadata.MediaType

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.7), lineWidth: 0.5)
            )
            .foregroundColor(.white)
    }

    private var text: String {
        switch type {
        case .photo: return "PHOTO"
        case .live: return "LIVE"
        case .video: return "VIDEO"
        case .gif: return "GIF"
        }
    }
}

private struct AlbumFilterView: View {
    @Binding var selectedAlbum: String
    let albums: [String]

    var body: some View {
        HStack {
            Text("筛选相册")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Menu {
                ForEach(albums, id: \.self) { album in
                    Button {
                        selectedAlbum = album
                    } label: {
                        if selectedAlbum == album {
                            Label(album, systemImage: "checkmark")
                        } else {
                            Text(album)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedAlbum)
                        .font(.subheadline.bold())
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground), in: Capsule())
            }
        }
    }
}
