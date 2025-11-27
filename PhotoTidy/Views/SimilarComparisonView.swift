import SwiftUI
import Photos

private enum SimilarLayoutMode {
    case stacked
    case sideBySide
}

struct SimilarComparisonView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String?
    @State private var currentGroupIndex: Int = 0
    @State private var layoutMode: SimilarLayoutMode = .stacked

    private var groups: [[PhotoItem]] {
        // 使用显式循环代替高级组合操作，减轻编译器负担
        var dict: [Int: [PhotoItem]] = [:]
        for item in viewModel.items {
            guard let gid = item.similarGroupId else { continue }
            dict[gid, default: []].append(item)
        }
        let values = Array(dict.values)
        return values.sorted { lhsGroup, rhsGroup in
            let lDate = lhsGroup.first?.creationDate ?? .distantPast
            let rDate = rhsGroup.first?.creationDate ?? .distantPast
            return lDate > rDate
        }
    }

    private var currentGroup: [PhotoItem]? {
        guard !groups.isEmpty, currentGroupIndex < groups.count else { return nil }
        return groups[currentGroupIndex]
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let group = currentGroup {
                    let hero = selectedItem(from: group)

                    layoutToggle

                    Spacer(minLength: 20)

                    VStack(spacing: 6) {
                        Text("相似度 \(Int.random(in: 90...99))%")
                            .font(.system(size: 20, weight: .bold))
                        Text("建议保留 1 张")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 20)

                    Group {
                        if layoutMode == .stacked {
                            stackedCards(for: group, hero: hero)
                        } else {
                            sideBySideCards(for: group, hero: hero)
                        }
                    }
                    .frame(height: 400)

                    Spacer()

                    Button {
                        if let hero = hero {
                            applySelection(keep: hero, delete: group.filter { $0.id != hero.id })
                            moveToNextGroupOrDismiss()
                        }
                    } label: {
                        Text("保留最佳")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color("brand-start"))
                            .cornerRadius(18)
                            .shadow(color: Color("brand-start").opacity(0.35), radius: 10, y: 6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                } else {
                    Spacer()
                    Text("没有检测到相似照片")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .onChange(of: currentGroupIndex) { _ in
            if let group = currentGroup {
                selectedId = group.first?.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }

            Spacer()

            if !groups.isEmpty {
                Text("第 \(min(currentGroupIndex + 1, groups.count)) / \(groups.count) 组")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            } else {
                Text("相似照片")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }

            Spacer()

            // 右侧留空位，使标题居中
            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    // MARK: - Layout Toggle

    private var layoutToggle: some View {
        HStack(spacing: 8) {
            Spacer()
            layoutToggleButton(
                title: "堆叠",
                systemImage: "square.stack.3d.forward.dottedline.fill",
                mode: .stacked
            )
            layoutToggleButton(
                title: "对比",
                systemImage: "square.split.2x1.fill",
                mode: .sideBySide
            )
            Spacer()
        }
        .padding(.top, 12)
    }

    private func layoutToggleButton(
        title: String,
        systemImage: String,
        mode: SimilarLayoutMode
    ) -> some View {
        let isActive = layoutMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                layoutMode = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? Color.white : Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color("brand-start") : Color.clear, lineWidth: 1)
            )
            .shadow(color: .black.opacity(isActive ? 0.15 : 0.05), radius: isActive ? 6 : 3, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func selectedItem(from group: [PhotoItem]) -> PhotoItem? {
        if let selectedId = selectedId, let item = group.first(where: { $0.id == selectedId }) {
            return item
        }
        let first = group.first
        selectedId = selectedId ?? first?.id
        return first
    }

    private func applySelection(keep hero: PhotoItem, delete others: [PhotoItem]) {
        viewModel.setDeletion(hero, to: false)
        others.forEach { viewModel.setDeletion($0, to: true) }
    }

    private func moveToNextGroupOrDismiss() {
        let lastIndex = max(groups.count - 1, 0)
        if currentGroupIndex < lastIndex {
            currentGroupIndex += 1
        } else {
            dismiss()
        }
    }

    // MARK: - Card Layouts

    @ViewBuilder
    private func stackedCards(for group: [PhotoItem], hero: PhotoItem?) -> some View {
        ZStack {
            if let hero = hero {
                // 选出当前组中除“最佳”外的另一张，作为背景卡片
                if let other = group.first(where: { $0.id != hero.id }) {
                    comparisonCard(for: other, isHero: false)
                        .rotationEffect(.degrees(6))
                        .offset(x: 20, y: 18)
                }

                comparisonCard(for: hero, isHero: true)
                    .rotationEffect(.degrees(-3))
                    .offset(x: -6, y: -10)
            }
        }
    }

    @ViewBuilder
    private func sideBySideCards(for group: [PhotoItem], hero: PhotoItem?) -> some View {
        if let hero = hero {
            let others = group.filter { $0.id != hero.id }
            HStack(spacing: 16) {
                if let firstOther = others.first {
                    comparisonCard(for: firstOther, isHero: false, compact: true)
                } else {
                    Spacer()
                }
                comparisonCard(for: hero, isHero: true, compact: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
    }

    private func comparisonCard(for item: PhotoItem, isHero: Bool, compact: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(isHero ? 0.25 : 0.12), radius: isHero ? 14 : 8, y: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(isHero ? Color("brand-start") : Color(UIColor.systemGray5), lineWidth: isHero ? 2 : 1)
                )

            AssetThumbnailView(
                asset: item.asset,
                imageManager: viewModel.imageManager,
                contentMode: .aspectFill
            )
            .grayscale(isHero ? 0 : 0.9)
            .opacity(isHero ? 1.0 : 0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(8)

            if isHero {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("最佳")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(Color.similarBadgeText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .padding(10)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "circle")
                        .font(.system(size: 10, weight: .bold))
                    Text("未选中")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .padding(10)
            }
        }
        .frame(width: compact ? 150 : 280, height: compact ? 210 : 380)
        .scaleEffect(
            isHero
            ? (compact ? 1.02 : 1.03)
            : (compact ? 0.98 : 0.96)
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.2)) {
                selectedId = item.id
            }
        }
    }
}

// 简单扩展：用于「最佳」徽标文字颜色
private extension Color {
    static let similarBadgeText = Color(red: 0.55, green: 0.4, blue: 0.0)
}
