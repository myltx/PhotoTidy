import Foundation
import Combine

@MainActor
final class PhotoStoreFacade: ObservableObject {
    static let shared = PhotoStoreFacade()

    @Published private(set) var feeds: [PhotoQueryIntent: PhotoFeedState] = [:]
    @Published private(set) var dashboard: DashboardSnapshot
    @Published private(set) var timeline: [TimelineBucketSnapshot]
    @Published private(set) var availableMonths: [PhotoAssetMetadata.MonthKey]
    @Published private(set) var prefetchLog: [PhotoStoreEventLog] = []

    private let store: PhotoStore

    init(store: PhotoStore = PhotoStore()) {
        self.store = store
        self.dashboard = DashboardSnapshot(
            generatedAt: Date(),
            totals: [],
            progressMeters: [],
            pendingDeletion: 0,
            skipped: 0,
            monthlyHighlights: [],
            storageUsage: DeviceStorageUsage(totalBytes: 0, usedBytes: 0, freeBytes: 0, clearableBytes: 0)
        )
        self.timeline = []
        self.availableMonths = []
        Task {
            await self.bootstrap()
        }
    }

    func feedState(for intent: PhotoQueryIntent) -> PhotoFeedState {
        if let state = feeds[intent] {
            return state
        }
        let placeholder = PhotoFeedState(intent: intent, items: [], cursor: nil, status: .loading)
        feeds[intent] = placeholder
        Task {
            await self.bootstrapFeed(intent: intent)
        }
        return placeholder
    }

    func requestNextPage(intent: PhotoQueryIntent) {
        Task {
            let state = await store.requestNextPage(intent: intent)
            await MainActor.run {
                self.feeds[intent] = state
            }
        }
    }

    func refreshDashboard() {
        Task {
            let snapshot = await store.dashboardSnapshot()
            await MainActor.run {
                self.dashboard = snapshot
            }
        }
    }

    func refreshTimeline() {
        Task {
            let newTimeline = await store.timelineBuckets()
            let months = await store.availableMonths()
            await MainActor.run {
                self.timeline = newTimeline
                self.availableMonths = months
            }
        }
    }

    func refreshDiagnostics() async {
        let log = await store.prefetchLog()
        await MainActor.run {
            self.prefetchLog = log
        }
    }

    private func bootstrap() async {
        let dash = await store.dashboardSnapshot()
        let timeline = await store.timelineBuckets()
        let monthKeys = await store.availableMonths()
        await MainActor.run {
            self.dashboard = dash
            self.timeline = timeline
            self.availableMonths = monthKeys
        }
        await refreshDiagnostics()
    }

    private func bootstrapFeed(intent: PhotoQueryIntent) async {
        let state = await store.ensureFeed(intent: intent)
        await MainActor.run {
            self.feeds[intent] = state
        }
    }
}
