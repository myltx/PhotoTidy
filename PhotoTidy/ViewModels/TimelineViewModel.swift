import Foundation
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published private(set) var buckets: [TimelineBucketSnapshot]
    @Published private(set) var months: [PhotoAssetMetadata.MonthKey]
    @Published private(set) var yearSections: [YearSectionModel] = []

    private let facade: PhotoStoreFacade
    private var cancellables: Set<AnyCancellable> = []

    init(facade: PhotoStoreFacade = .shared) {
        self.facade = facade
        self.buckets = facade.timeline
        self.months = facade.availableMonths
        bind()
        facade.refreshTimeline()
    }

    private func bind() {
        facade.$timeline
            .receive(on: RunLoop.main)
            .sink { [weak self] buckets in
                self?.buckets = buckets
                self?.rebuildSections()
            }
            .store(in: &cancellables)

        facade.$availableMonths
            .receive(on: RunLoop.main)
            .sink { [weak self] months in
                self?.months = months
                self?.rebuildSections()
            }
            .store(in: &cancellables)
    }

    private func rebuildSections() {
        let grouped = Dictionary(grouping: buckets) { $0.monthKey.year }
        yearSections = grouped.keys.sorted(by: >).map { year in
            let months = grouped[year]?.sorted(by: { $0.monthKey.month > $1.monthKey.month }) ?? []
            return YearSectionModel(year: year, months: months)
        }
    }

    struct YearSectionModel: Identifiable {
        let year: Int
        let months: [TimelineBucketSnapshot]

        var id: Int { year }
    }
}
