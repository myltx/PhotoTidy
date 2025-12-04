import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeader(title: "存储概览", subtitle: "手机容量与可释放空间")
                    storageOverview
                    SectionHeader(title: "待处理区域", subtitle: "待删除与待确认的数量")
                    pendingSection
                    SectionHeader(title: "分类统计", subtitle: "常见清理类别实时数量")
                    statGrid
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("清理仪表盘")
        }
    }

    private var storageOverview: some View {
        StorageOverviewCard(storage: viewModel.snapshot.storageUsage)
    }

    private var pendingSection: some View {
        HStack(spacing: 12) {
            PendingMetricCard(
                title: "待删区",
                value: viewModel.snapshot.pendingDeletion,
                icon: "trash",
                gradient: ["#F87171", "#EF4444"]
            )
            PendingMetricCard(
                title: "待确认",
                value: viewModel.snapshot.skipped,
                icon: "rectangle.dashed",
                gradient: ["#FCD34D", "#FBBF24"]
            )
        }
    }

    private var statGrid: some View {
        let stats = [
            DashboardStat(label: "总数", value: viewModel.snapshot.value(for: "总数") ?? 0, colors: ["#6366F1", "#8B5CF6"]),
            DashboardStat(label: "大文件", value: viewModel.snapshot.value(for: "大文件") ?? 0, colors: ["#F97316", "#FB923C"]),
            DashboardStat(label: "相似图片", value: viewModel.snapshot.value(for: "相似") ?? 0, colors: ["#EC4899", "#F472B6"]),
            DashboardStat(label: "文档/截图", value: documentScreenshotTotal, colors: ["#0EA5E9", "#38BDF8"]),
            DashboardStat(label: "模糊照片", value: viewModel.snapshot.value(for: "模糊") ?? 0, colors: ["#10B981", "#34D399"])
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(stats) { stat in
                DashboardMetricCard(stat: stat)
            }
        }
    }

    private var documentScreenshotTotal: Int {
        let docs = viewModel.snapshot.value(for: "文档") ?? 0
        let shots = viewModel.snapshot.value(for: "截图") ?? 0
        return docs + shots
    }

}

private struct StorageOverviewCard: View {
    let storage: DeviceStorageUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("手机存储")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(storage.formattedTotal)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }
                Spacer()
                Gauge(value: usageRatio) {
                    Text("")
                } currentValueLabel: {
                    Text(String(format: "%.0f%%", usageRatio * 100))
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Gradient(colors: [Color(hex: "#34D399"), Color(hex: "#10B981")]))
            }
            Divider().overlay(Color.white.opacity(0.2))
            HStack(spacing: 12) {
                storageChip(title: "已使用", value: storage.formattedUsed, color: "#F97316")
                storageChip(title: "可清理", value: storage.formattedClearable, color: "#10B981")
                storageChip(title: "剩余", value: storage.formattedFree, color: "#6366F1")
            }
        }
        .padding()
        .background(
            LinearGradient(colors: [Color(hex: "#1F1C2C"), Color(hex: "#928DAB")],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var usageRatio: Double {
        guard storage.totalBytes > 0 else { return 0 }
        return Double(storage.usedBytes) / Double(storage.totalBytes)
    }

    private func storageChip(title: String, value: String, color: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: color).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct PendingMetricCard: View {
    let title: String
    let value: Int
    let icon: String
    let gradient: [String]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(value)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Spacer()
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: gradient.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DashboardStat: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let colors: [String]
}

private struct DashboardMetricCard: View {
    let stat: DashboardStat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stat.label)
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
            Text("\(stat.value)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: stat.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
