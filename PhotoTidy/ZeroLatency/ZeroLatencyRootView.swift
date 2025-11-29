import SwiftUI
import Photos
import UIKit

struct ZeroLatencyRootView: View {
    @StateObject private var viewModel = ZeroLatencyPhotoViewModel()
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            content
        }
        .onAppear {
            viewModel.onAppear()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.authorizationStatus {
        case .authorized, .limited:
            mainContent
        case .notDetermined:
            ZeroLatencyPermissionRequestView {
                viewModel.requestAuthorization()
            }
        default:
            PermissionDeniedView()
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZeroLatencyHeaderView(snapshot: viewModel.dashboardSnapshot, analysisState: viewModel.analysisState)
                    .padding(.top, 32)
                ZeroLatencyRecentPreviewRow(previewItems: viewModel.dashboardSnapshot.recentPreview)
                gridSection
            }
            .padding(.horizontal, 20)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.gridItems.count)
    }

    private var gridSection: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            if viewModel.gridItems.isEmpty {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 120)
                        .redacted(reason: .placeholder)
                        .shimmer()
                }
            } else {
                ForEach(Array(viewModel.gridItems.enumerated()), id: \.1.id) { index, item in
                    ZeroLatencyThumbnailCell(item: item, imageCache: viewModel.imageCache)
                        .onAppear {
                            viewModel.thumbnailDidAppear(at: index)
                            let lower = max(0, index - 6)
                            let upper = min(viewModel.gridItems.count, index + 12)
                            viewModel.reportVisibleRange(lower..<upper)
                        }
                }
            }
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Header & Preview

struct ZeroLatencyHeaderView: View {
    let snapshot: DashboardSnapshot
    let analysisState: AnalysisState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .padding(12)
                    .background(Color("brand-start").opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading) {
                    Text("PhotoTidy")
                        .font(.title2).bold()
                    Text("零延迟相册加载架构")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(analysisState.statusText)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("照片总数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(snapshot.totalCount)")
                        .font(.largeTitle).bold()
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("最近更新")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(snapshot.lastUpdated == .distantPast ? "尚未分析" : snapshot.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                        .font(.title3).bold()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

struct ZeroLatencyRecentPreviewRow: View {
    let previewItems: [RecentPreviewItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近缩略图")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if previewItems.isEmpty {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 80, height: 80)
                                .redacted(reason: .placeholder)
                                .shimmer()
                        }
                    } else {
                        ForEach(previewItems) { item in
                            VStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray.opacity(0.12))
                                    .frame(width: 80, height: 80)
                                Text(item.createdAt, format: Date.FormatStyle().month(.twoDigits).day(.twoDigits))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ZeroLatencyPermissionRequestView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(Color("brand-start"))
            Text("欢迎使用 PhotoTidy")
                .font(.title2).bold()
            Text("我们需要访问您的相册以载入缓存、执行本地分析。所有计算都在设备完成，绝不上传到云端。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: action) {
                Text("授权读取相册")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(LinearGradient(colors: [Color("brand-start"), Color("brand-end")], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Thumbnail Cell

struct ZeroLatencyThumbnailCell: View {
    let item: AssetItem
    let imageCache: ImageCache
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
                    .frame(height: 120)
                    .overlay(
                        VStack {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                            Text(item.creationDate, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    )
                    .redacted(reason: .placeholder)
            }
        }
        .task(id: item.id) {
            image = await imageCache.requestThumbnail(for: item.asset, targetSize: CGSize(width: 200, height: 200))
        }
    }
}

// MARK: - Skeleton shimmer

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0), location: phase),
                    .init(color: .white.opacity(0.4), location: phase + 0.1),
                    .init(color: .white.opacity(0), location: phase + 0.2)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.plusLighter)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
