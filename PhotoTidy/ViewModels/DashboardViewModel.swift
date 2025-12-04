import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot
    @Published private(set) var timeline: [TimelineBucketSnapshot]

    private let facade: PhotoStoreFacade
    private var cancellables: Set<AnyCancellable> = []

    init(facade: PhotoStoreFacade = .shared) {
        self.facade = facade
        self.snapshot = facade.dashboard
        self.timeline = facade.timeline
        bind()
        facade.refreshDashboard()
        facade.refreshTimeline()
    }

    private func bind() {
        facade.$dashboard
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.snapshot = snapshot
            }
            .store(in: &cancellables)

        facade.$timeline
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.timeline = value
            }
            .store(in: &cancellables)
    }
}
