import Foundation
import Combine
import Photos

final class TimeMachineTimelineViewModel: ObservableObject {
    struct YearSection: Identifiable, Equatable {
        let year: Int
        let months: [MonthInfo]

        var id: Int { year }
    }

    @Published private(set) var sections: [YearSection] = []

    private let dataSource: PhotoCleanupViewModel
    private var cancellables: Set<AnyCancellable> = []
    private let calendar = Calendar.current

    init(dataSource: PhotoCleanupViewModel) {
        self.dataSource = dataSource
        bind()
        rebuildTimeline(
            items: dataSource.items,
            skippedRecords: dataSource.skippedPhotoRecords,
            snapshots: dataSource.timeMachineSnapshots
        )
    }

    private func bind() {
        Publishers.CombineLatest3(
            dataSource.$items,
            dataSource.$skippedPhotoRecords,
            dataSource.$timeMachineSnapshots
        )
        .receive(on: DispatchQueue.global(qos: .userInitiated))
        .sink { [weak self] items, skipped, snapshots in
            self?.rebuildTimeline(items: items, skippedRecords: skipped, snapshots: snapshots)
        }
        .store(in: &cancellables)
    }

    private func rebuildTimeline(
        items: [PhotoItem],
        skippedRecords: [SkippedPhotoRecord],
        snapshots: [String: TimeMachineMonthProgress]
    ) {
        guard !items.isEmpty || !skippedRecords.isEmpty || !snapshots.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.sections = []
            }
            return
        }

        var accumulators: [String: MonthAccumulator] = [:]
        var photoDates: [String: Date] = [:]

        for item in items {
            guard let date = item.creationDate else { continue }
            let comps = calendar.dateComponents([.year, .month], from: date)
            guard let year = comps.year, let month = comps.month else { continue }
            let key = monthKey(year: year, month: month)
            var entry = accumulators[key] ?? MonthAccumulator()
            entry.totalPhotos += 1
            if item.markedForDeletion { entry.pendingDeleteCount += 1 }
            accumulators[key] = entry
            photoDates[item.id] = date
        }

        let skippedCounts = buildSkippedCounts(from: skippedRecords, photoDates: photoDates)

        var monthInfos: [MonthInfo] = []
        let keys = Set(accumulators.keys)
            .union(skippedCounts.keys)
            .union(snapshots.keys)

        for key in keys {
            guard let comps = components(from: key) else { continue }
            let total = accumulators[key]?.totalPhotos ?? 0
            let pending = accumulators[key]?.pendingDeleteCount ?? 0
            let skipped = skippedCounts[key] ?? 0
            let confirmed = snapshots[key]?.confirmedPhotoIds.count ?? 0
            let info = MonthInfo(
                year: comps.year,
                month: comps.month,
                totalPhotos: total,
                skippedCount: skipped,
                pendingDeleteCount: pending,
                confirmedCount: confirmed
            )
            monthInfos.append(info)
        }

        monthInfos.sort { lhs, rhs in
            lhs.year == rhs.year ? lhs.month > rhs.month : lhs.year > rhs.year
        }

        let grouped = Dictionary(grouping: monthInfos) { $0.year }
        let sections = grouped.map { year, months in
            YearSection(year: year, months: months.sorted { $0.month > $1.month })
        }
        .sorted { $0.year > $1.year }

        DispatchQueue.main.async { [weak self] in
            self?.sections = sections
        }
    }

    private func buildSkippedCounts(
        from records: [SkippedPhotoRecord],
        photoDates: [String: Date]
    ) -> [String: Int] {
        let filtered = records.filter { $0.source == .timeMachine }
        guard !filtered.isEmpty else { return [:] }

        var counts: [String: Int] = [:]
        var missingIds: [String] = []

        for record in filtered {
            if let date = photoDates[record.photoId] {
                accumulateSkip(for: date, counts: &counts)
            } else {
                missingIds.append(record.photoId)
            }
        }

        if !missingIds.isEmpty {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: missingIds, options: nil)
            fetched.enumerateObjects { [weak self] asset, _, _ in
                guard
                    let self,
                    let date = asset.creationDate
                else { return }
                self.accumulateSkip(for: date, counts: &counts)
            }
        }

        return counts
    }

    private func accumulateSkip(for date: Date, counts: inout [String: Int]) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return }
        let key = monthKey(year: year, month: month)
        counts[key, default: 0] += 1
    }

    private func monthKey(year: Int, month: Int) -> String {
        "\(year)-\(month)"
    }

    private func components(from key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return nil
        }
        return (year, month)
    }
}

private struct MonthAccumulator {
    var totalPhotos: Int = 0
    var pendingDeleteCount: Int = 0
}
