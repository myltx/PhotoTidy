import SwiftUI

struct ContentView: View {
    @State private var selection: AppTab = .dashboard
    @State private var tabBarHidden = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContent(for: selection)
            }
            if !tabBarHidden {
                CustomTabBar(selection: $selection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tabBarHidden)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView()
        case .carousel:
            CarouselReviewView()
        case .grouped:
            GroupedReviewView()
        case .ranked:
            RankedReviewView()
        case .timeline:
            TimelineView()
        case .decision:
            DecisionCenterContainerView(tabBarHidden: $tabBarHidden)
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case dashboard
    case carousel
    case grouped
    case ranked
    case timeline
    case decision

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "仪表盘"
        case .carousel: return "滑动"
        case .grouped: return "相似"
        case .ranked: return "专项"
        case .timeline: return "时光机"
        case .decision: return "决策"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "speedometer"
        case .carousel: return "square.stack.3d.forward.dottedline"
        case .grouped: return "square.grid.2x2"
        case .ranked: return "chart.bar"
        case .timeline: return "calendar"
        case .decision: return "tray.full"
        }
    }
}

private struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2)
                    }
                    .foregroundColor(selection == tab ? .white : .secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == tab ? Color.accentColor : Color(.secondarySystemBackground))
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct DecisionCenterContainerView: View {
    @Binding var tabBarHidden: Bool

    var body: some View {
        NavigationStack {
            DecisionCenterView(onDetailVisibilityChange: handleVisibilityChange)
                .navigationTitle("决策中心")
        }
        .onAppear {
            handleVisibilityChange(false)
        }
    }

    private func handleVisibilityChange(_ hidden: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            tabBarHidden = hidden
        }
    }
}
