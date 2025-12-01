import SwiftUI
import Photos

struct TimeMachineZeroLatencyContainerView: View {
    @StateObject private var viewModel = TimeMachineZeroLatencyViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("时光机")
        }
        .onAppear {
            viewModel.onAppear()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.authorizationStatus {
        case .authorized, .limited:
            sectionsView
        case .notDetermined:
            PermissionPrompt {
                viewModel.requestAuthorization()
            }
        default:
            PermissionDeniedView()
        }
    }

    private var sectionsView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(viewModel.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(section.year) 年")
                            .font(.title2.bold())
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 12) {
                            ForEach(section.months) { month in
                                NavigationLink {
                                    TimeMachineMonthDetailView(
                                        viewModel: viewModel.detailViewModel(for: month)
                                    )
                                } label: {
                                    MonthCard(meta: month)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }
}

private struct PermissionPrompt: View {
    let action: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("需要相册权限")
                .font(.title2).bold()
            Text("请允许 PhotoTidy 访问您的相册，以便展示时光机数据。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("授权访问", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct MonthCard: View {
    let meta: MonthInfo

    var body: some View {
        VStack(spacing: 8) {
            Text("\(meta.month) 月")
                .font(.headline)
            Text(meta.status.title)
                .font(.caption)
                .foregroundColor(color)
            ProgressView(value: meta.progress)
                .progressViewStyle(.linear)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var color: Color {
        switch meta.status {
        case .notStarted: return .secondary
        case .inProgress: return .orange
        case .completed: return .green
        }
    }
}

private struct TimeMachineMonthDetailView: View {
    @StateObject var viewModel: TimeMachineMonthDetailViewModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(viewModel.assetIds, id: \.self) { id in
                    ZStack {
                        if let image = viewModel.thumbnails[id] {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.gray.opacity(0.2)
                                .overlay(ProgressView())
                        }
                    }
                    .frame(height: 120)
                    .clipped()
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentId: id)
                    }
                }
            }
            .padding(6)
        }
        .navigationTitle("\(viewModel.assetIds.count) 张照片")
        .onDisappear {
            viewModel.cancelCaching()
        }
    }
}
