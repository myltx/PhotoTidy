import SwiftUI
import Photos

struct DashboardView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @State private var showTrashSheet = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                headerSection
                storageCard
                featuredCleanerCard
                smartCleanupGrid
                similarPreviewCard
                blurryPreviewCard
                screenshotPreviewCard
                largeFilesPreviewCard
                trashPreviewCard
                successCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .padding(.bottom, 120)
        }
        .background(Color(UIColor.systemGray6))
        .sheet(isPresented: $showTrashSheet) {
            PendingDeletionView(viewModel: viewModel)
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Sections
private extension DashboardView {
    var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("早上好")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("相册清理")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            Spacer()
            Image(systemName: "person.fill")
                .font(.system(size: 28))
                .foregroundColor(.gray)
                .frame(width: 48, height: 48)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        }
    }

    var storageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本机存储")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text("已用 186 GB / 256 GB")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                Spacer()
                Text("82%")
                    .font(.title3).bold()
                    .foregroundColor(.white)
            }
            ProgressView(value: 0.82)
                .progressViewStyle(.linear)
                .tint(.white)
            Text("预计可释放 ~\(viewModel.pendingDeletionTotalSize.fileSizeDescription)")
                .font(.caption).bold()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
                .foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color("brand-start"), Color("brand-end")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(28)
        .shadow(color: Color("brand-start").opacity(0.35), radius: 20, y: 10)
    }

    var featuredCleanerCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            VStack(alignment: .leading, spacing: 12) {
                Text("全相册整理")
                    .font(.title2).bold()
                Text("左滑删除，右滑保留，AI 会自动识别模糊与相似照片。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button(action: { viewModel.showCleaner(filter: .all) }) {
                    Label("开始整理", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color("brand-start"))
                        .clipShape(Capsule())
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
    }

    var smartCleanupGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("智能整理")
                .font(.title2).bold()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                SmartCategoryCard(title: "相似照片", subtitle: "\(viewModel.similarItemsCount) 张", icon: "rectangle.stack", iconColor: .indigo) {
                    viewModel.showDetail(.similar)
                }
                SmartCategoryCard(title: "模糊照片", subtitle: "\(viewModel.blurredItemsCount) 张", icon: "eye.slash", iconColor: .orange) {
                    viewModel.showDetail(.blurry)
                }
                SmartCategoryCard(title: "截屏/文档", subtitle: "\(viewModel.screenshotItemsCount) 张", icon: "doc.richtext", iconColor: .blue) {
                    viewModel.showDetail(.screenshots)
                }
                SmartCategoryCard(title: "大文件", subtitle: viewModel.largeFilesSize.fileSizeDescription, icon: "film", iconColor: .green) {
                    viewModel.showDetail(.largeFiles)
                }
            }
        }
    }

    var similarPreviewCard: some View {
        let items = viewModel.items.filter { $0.similarGroupId != nil }.prefix(2)
        return DashboardPreviewCard(
            title: "相似照片",
            subtitle: "AI 推荐保留 1 张",
            buttonTitle: "快速清理",
            action: { viewModel.showDetail(.similar) }
        ) {
            HStack(spacing: -40) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                        .frame(width: 140, height: 180)
                        .cornerRadius(22)
                        .shadow(radius: 5)
                        .rotationEffect(.degrees(index == 0 ? -6 : 4))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    var blurryPreviewCard: some View {
        let items = viewModel.items.filter { $0.isBlurredOrShaky }.prefix(4)
        return DashboardPreviewCard(
            title: "模糊检测",
            subtitle: "已选 \(items.count) 张",
            buttonTitle: "全部查看",
            action: { viewModel.showDetail(.blurry) }
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                        .aspectRatio(1, contentMode: .fit)
                        .cornerRadius(18)
                        .overlay(
                            Text("模糊").font(.caption2).bold()
                                .padding(6)
                                .background(Color.red.opacity(0.8))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                                .padding(8),
                            alignment: .bottomLeading
                        )
                }
            }
        }
    }

    var screenshotPreviewCard: some View {
        let items = viewModel.items.filter { $0.isScreenshot || $0.isDocumentLike }.prefix(3)
        return DashboardPreviewCard(
            title: "截图与文档",
            subtitle: "高频票据与聊天截图",
            buttonTitle: "整理截屏",
            action: { viewModel.showDetail(.screenshots) }
        ) {
            VStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 12) {
                        AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                            .frame(width: 50, height: 70)
                            .cornerRadius(12)
                        VStack(alignment: .leading) {
                            Text(item.asset.originalFilename)
                                .font(.subheadline).bold()
                            Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "未知日期")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    var largeFilesPreviewCard: some View {
        let largeItems = viewModel.items.filter { $0.isLargeFile }.sorted { $0.fileSize > $1.fileSize }
        let hero = largeItems.first
        return DashboardPreviewCard(
            title: "大文件清理",
            subtitle: "占用空间 Top 10",
            buttonTitle: "查看详情",
            action: { viewModel.showDetail(.largeFiles) }
        ) {
            if let hero = hero {
                VStack(alignment: .leading, spacing: 8) {
                    AssetThumbnailView(asset: hero.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                        .frame(height: 160)
                        .cornerRadius(18)
                        .overlay(alignment: .topTrailing) {
                            Text(hero.fileSize.fileSizeDescription)
                                .font(.caption2).bold()
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(10)
                        }
                    ForEach(largeItems.dropFirst().prefix(3), id: \.id) { item in
                        HStack {
                            AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                                .frame(width: 44, height: 44)
                                .cornerRadius(10)
                            VStack(alignment: .leading) {
                                Text(item.asset.originalFilename).font(.subheadline).bold()
                                Text(item.fileSize.fileSizeDescription).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            } else {
                Text("暂无大文件").foregroundColor(.secondary)
            }
        }
    }

    var trashPreviewCard: some View {
        DashboardPreviewCard(
            title: "待删区",
            subtitle: "共 \(viewModel.pendingDeletionItems.count) 张 • 可释放 \(viewModel.pendingDeletionTotalSize.fileSizeDescription)",
            buttonTitle: "查看",
            action: { showTrashSheet = true }
        ) {
            let items = viewModel.pendingDeletionItems.prefix(4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    AssetThumbnailView(asset: item.asset, imageManager: viewModel.imageManager, contentMode: .aspectFill)
                        .aspectRatio(1, contentMode: .fit)
                        .cornerRadius(14)
                        .shadow(radius: 2)
                }
                if viewModel.pendingDeletionItems.count > 4 {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(UIColor.systemGray5))
                        Text("+\(viewModel.pendingDeletionItems.count - 4)")
                            .font(.headline).foregroundColor(.secondary)
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    var successCard: some View {
        DashboardPreviewCard(
            title: "清理完成",
            subtitle: "最近一次清理共释放 1.8 GB",
            buttonTitle: "返回首页",
            action: { viewModel.showDetail(.success) }
        ) {
            VStack(spacing: 12) {
                Text("保持相册整洁如新").font(.subheadline).foregroundColor(.secondary)
                Text("继续智能整理，让设备更轻松。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Components
private struct SmartCategoryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 48, height: 48)
                    .background(iconColor.opacity(0.12))
                    .cornerRadius(18)
                Text(title)
                    .font(.headline).bold()
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(22)
            .shadow(color: .black.opacity(0.05), radius: 6, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardPreviewCard<Content: View>: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).bold()
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.caption).bold()
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(UIColor.systemGray5))
                        .clipShape(Capsule())
                }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(26)
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }
}
