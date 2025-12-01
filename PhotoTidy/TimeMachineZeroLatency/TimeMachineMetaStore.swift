import Foundation
import Photos

actor TimeMachineMetaStore {
    private var monthInfos: [String: MonthInfo] = [:]
    private var photoDateCache: [String: Date] = [:]
    private let calendar = Calendar.current

    func rebuild(
        snapshot: MetadataSnapshot,
        progressStore: TimeMachineProgressStore,
        skippedStore: SkippedPhotoStore
    ) async {
        var builder: [String: (year: Int, month: Int, total: Int, skipped: Int, pending: Int, confirmed: Int)] = [:]

        for entry in snapshot.monthTotals {
            builder[entry.id] = (
                year: entry.year,
                month: entry.month,
                total: entry.total,
                skipped: 0,
                pending: 0,
                confirmed: 0
            )
        }

        let progresses = progressStore.allProgresses()
        for progress in progresses {
            let key = TimeMachineMetaStore.key(year: progress.year, month: progress.month)
            var counts = builder[key] ?? (
                year: progress.year,
                month: progress.month,
                total: 0,
                skipped: 0,
                pending: 0,
                confirmed: 0
            )
            counts.pending = progress.selectedPhotoIds.count
            counts.confirmed = progress.confirmedPhotoIds.count
            builder[key] = counts
        }

        let skipped = skippedStore.allRecords().filter { $0.source == .timeMachine }
        if !skipped.isEmpty {
            let ids = skipped.map(\.photoId)
            let fetchedDates = await fetchCreationDates(for: ids)
            for record in skipped {
                guard let date = fetchedDates[record.photoId] else { continue }
                let comps = calendar.dateComponents([.year, .month], from: date)
                guard let year = comps.year, let month = comps.month else { continue }
                let key = TimeMachineMetaStore.key(year: year, month: month)
                var counts = builder[key] ?? (year: year, month: month, total: 0, skipped: 0, pending: 0, confirmed: 0)
                counts.skipped += 1
                builder[key] = counts
            }
        }

        var updated: [String: MonthInfo] = [:]
        for (key, counts) in builder {
            let info = MonthInfo(
                year: counts.year,
                month: counts.month,
                totalPhotos: counts.total,
                skippedCount: counts.skipped,
                pendingDeleteCount: counts.pending,
                confirmedCount: counts.confirmed
            )
            updated[key] = info
        }
        monthInfos = updated
    }

    func sections() -> [TimeMachineMonthSection] {
        let grouped = Dictionary(grouping: monthInfos.values) { $0.year }
        let yearSections = grouped.map { year, months -> TimeMachineMonthSection in
            let sorted = months.sorted { $0.month < $1.month }
            return TimeMachineMonthSection(year: year, months: sorted)
        }
        return yearSections.sorted { $0.year > $1.year }
    }

    private func fetchCreationDates(for identifiers: [String]) async -> [String: Date] {
        guard !identifiers.isEmpty else { return [:] }
        var result: [String: Date] = [:]
        var missing: [String] = []
        for id in identifiers {
            if let cached = photoDateCache[id] {
                result[id] = cached
            } else {
                missing.append(id)
            }
        }
        guard !missing.isEmpty else { return result }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: missing, options: nil)
        assets.enumerateObjects { asset, _, _ in
            let date = asset.creationDate ?? asset.modificationDate
            if let date {
                self.photoDateCache[asset.localIdentifier] = date
                result[asset.localIdentifier] = date
            }
        }
        return result
    }

    private static func key(year: Int, month: Int) -> String {
        "\(year)-\(month)"
    }
}
