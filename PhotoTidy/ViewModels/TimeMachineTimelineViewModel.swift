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
    private let processingQueue = DispatchQueue(label: "TimeMachineTimelineViewModel.queue", qos: .userInitiated)
    private let calendar = Calendar.current

    private var itemMetrics: [String: ItemMetrics] = [:]
    private var skippedMetrics: [String: Int] = [:]
    private var confirmedMetrics: [String: Int] = [:]
    private var monthInfos: [String: MonthInfo] = [:]
    private var monthComponents: [String: (year: Int, month: Int)] = [:]
    private var photoDates: [String: Date] = [:]
    private var cachedSkippedRecords: [SkippedPhotoRecord] = []
    private var availableYears: [Int] = []

    init(dataSource: PhotoCleanupViewModel) {
        self.dataSource = dataSource
        bind()
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.handleItemsUpdate(dataSource.items)
            self.handleSkippedRecords(dataSource.skippedPhotoRecords, cacheRecords: true)
            self.handleSnapshotUpdate(dataSource.timeMachineSnapshots)
            self.ensureYearRangeFromItems(dataSource.items)
            self.ensureYearRangeFromLibraryIfNeeded()
        }
    }

    private func bind() {
        dataSource.$items
            .receive(on: processingQueue)
            .sink { [weak self] items in
                self?.handleItemsUpdate(items)
            }
            .store(in: &cancellables)

        dataSource.$skippedPhotoRecords
            .receive(on: processingQueue)
            .sink { [weak self] records in
                self?.handleSkippedRecords(records, cacheRecords: true)
            }
            .store(in: &cancellables)

        dataSource.$timeMachineSnapshots
            .receive(on: processingQueue)
            .sink { [weak self] snapshots in
                self?.handleSnapshotUpdate(snapshots)
            }
            .store(in: &cancellables)
    }

    private func handleItemsUpdate(_ items: [PhotoItem]) {
        var newMetrics: [String: ItemMetrics] = [:]
        var newDates: [String: Date] = [:]

        for item in items {
            let date = item.creationDate ?? Date()
            guard let comps = components(from: date) else { continue }
            let key = monthKey(year: comps.year, month: comps.month)
            var metrics = newMetrics[key] ?? ItemMetrics(year: comps.year, month: comps.month, totalPhotos: 0, pendingDeleteCount: 0)
            metrics.totalPhotos += 1
            if item.markedForDeletion {
                metrics.pendingDeleteCount += 1
            }
            newMetrics[key] = metrics
            newDates[item.id] = date
            monthComponents[key] = (comps.year, comps.month)
        }

        photoDates = newDates
        let changedKeys = diffKeys(old: itemMetrics, new: newMetrics)
        itemMetrics = newMetrics
        refreshMonthInfos(for: changedKeys)

        // 重新计算跳过数量，避免因为照片刚加载导致月份缺失
        rebuildSkippedMetricsFromCache()
        ensureYearRangeFromItems(items)
    }

    private func handleSkippedRecords(_ records: [SkippedPhotoRecord], cacheRecords: Bool) {
        if cacheRecords {
            cachedSkippedRecords = records
        }
        let newMetrics = buildSkippedMetrics(from: records)
        let changedKeys = diffKeys(old: skippedMetrics, new: newMetrics)
        skippedMetrics = newMetrics
        refreshMonthInfos(for: changedKeys)
    }

    private func handleSnapshotUpdate(_ snapshots: [String: TimeMachineMonthProgress]) {
        var newMetrics: [String: Int] = [:]
        for progress in snapshots.values {
            let key = monthKey(year: progress.year, month: progress.month)
            newMetrics[key] = progress.confirmedPhotoIds.count
            monthComponents[key] = (progress.year, progress.month)
        }

        let changedKeys = diffKeys(old: confirmedMetrics, new: newMetrics)
        confirmedMetrics = newMetrics
        refreshMonthInfos(for: changedKeys)
    }

    private func rebuildSkippedMetricsFromCache() {
        guard !cachedSkippedRecords.isEmpty else { return }
        let newMetrics = buildSkippedMetrics(from: cachedSkippedRecords)
        let changedKeys = diffKeys(old: skippedMetrics, new: newMetrics)
        guard !changedKeys.isEmpty else { return }
        skippedMetrics = newMetrics
        refreshMonthInfos(for: changedKeys)
    }

    private func buildSkippedMetrics(from records: [SkippedPhotoRecord]) -> [String: Int] {
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
            let fetchedDates = fetchCreationDates(for: missingIds)
            for (id, date) in fetchedDates {
                photoDates[id] = date
                accumulateSkip(for: date, counts: &counts)
            }
        }

        return counts
    }

    private func refreshMonthInfos(for keys: Set<String>) {
        guard !keys.isEmpty else { return }
        var changed = false

        for key in keys {
            let total = itemMetrics[key]?.totalPhotos ?? 0
            let pending = itemMetrics[key]?.pendingDeleteCount ?? 0
            let skipped = skippedMetrics[key] ?? 0
            let confirmed = confirmedMetrics[key] ?? 0

            let hasMetricsSource = itemMetrics[key] != nil
                || skippedMetrics[key] != nil
                || confirmedMetrics[key] != nil
            if !hasMetricsSource {
                continue
            }

            guard let comps = monthComponents[key] ?? components(fromKeyString: key) else { continue }
            let info = MonthInfo(
                year: comps.year,
                month: comps.month,
                totalPhotos: total,
                skippedCount: skipped,
                pendingDeleteCount: pending,
                confirmedCount: confirmed
            )
            if monthInfos[key] != info {
                monthInfos[key] = info
                changed = true
            }
            monthComponents[key] = comps
        }

        if changed {
            publishSections()
        }
    }

    private func publishSections() {
        let sortedInfos = monthInfos.values
            .sorted { lhs, rhs in
                lhs.year == rhs.year ? lhs.month > rhs.month : lhs.year > rhs.year
            }

        let grouped = Dictionary(grouping: sortedInfos) { $0.year }
        let builtSections: [YearSection]
        if availableYears.isEmpty {
            builtSections = grouped
                .map { year, months in
                    YearSection(year: year, months: months.sorted { $0.month > $1.month })
                }
                .sorted { $0.year > $1.year }
        } else {
            builtSections = availableYears.compactMap { year in
                let months = (1...12).compactMap { monthInfos[monthKey(year: year, month: $0)] }
                guard !months.isEmpty else { return nil }
                return YearSection(year: year, months: months.sorted { $0.month > $1.month })
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.sections = builtSections
        }
    }

    private func accumulateSkip(for date: Date, counts: inout [String: Int]) {
        guard let comps = components(from: date) else { return }
        let key = monthKey(year: comps.year, month: comps.month)
        counts[key, default: 0] += 1
        monthComponents[key] = (comps.year, comps.month)
    }

    private func fetchCreationDates(for identifiers: [String]) -> [String: Date] {
        guard !identifiers.isEmpty else { return [:] }
        var results: [String: Date] = [:]
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        fetchResult.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate {
                results[asset.localIdentifier] = date
            }
        }
        return results
    }

    private func monthKey(year: Int, month: Int) -> String {
        "\(year)-\(month)"
    }

    private func components(from date: Date) -> (year: Int, month: Int)? {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        return (year, month)
    }

    private func components(fromKeyString key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return nil }
        return (year, month)
    }

    private func ensureYearRangeFromItems(_ items: [PhotoItem]) {
        let years = items.compactMap { item -> Int? in
            guard let date = item.creationDate else { return nil }
            return calendar.component(.year, from: date)
        }
        if let minYear = years.min(), let maxYear = years.max() {
            updateAvailableYears(minYear: minYear, maxYear: maxYear)
        } else {
            ensureYearRangeFromLibraryIfNeeded()
        }
    }

    private func ensureYearRangeFromLibraryIfNeeded() {
        guard availableYears.isEmpty else { return }
        if let bounds = fetchYearBoundsFromLibrary() {
            updateAvailableYears(minYear: bounds.min, maxYear: bounds.max)
        } else {
            let currentYear = calendar.component(.year, from: Date())
            availableYears = [currentYear]
            ensurePlaceholdersForAvailableYears()
        }
    }

    private func fetchYearBoundsFromLibrary() -> (min: Int, max: Int)? {
        let ascending = PHFetchOptions()
        ascending.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        ascending.fetchLimit = 1
        let descending = PHFetchOptions()
        descending.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        descending.fetchLimit = 1

        guard
            let oldest = PHAsset.fetchAssets(with: ascending).firstObject?.creationDate,
            let newest = PHAsset.fetchAssets(with: descending).firstObject?.creationDate
        else {
            return nil
        }
        let minYear = calendar.component(.year, from: oldest)
        let maxYear = calendar.component(.year, from: newest)
        return (minYear, maxYear)
    }

    private func updateAvailableYears(minYear: Int, maxYear: Int) {
        let currentMin = availableYears.min()
        let currentMax = availableYears.max()
        let finalMin = currentMin.map { min($0, minYear) } ?? minYear
        let finalMax = currentMax.map { max($0, maxYear) } ?? maxYear
        if !availableYears.isEmpty,
           currentMin == finalMin,
           currentMax == finalMax {
            return
        }

        availableYears = Array(stride(from: finalMax, through: finalMin, by: -1))
        ensurePlaceholdersForAvailableYears()
    }

    private func ensurePlaceholdersForAvailableYears() {
        guard !availableYears.isEmpty else { return }
        var didAdd = false
        for year in availableYears {
            for month in 1...12 {
                let key = monthKey(year: year, month: month)
                guard monthInfos[key] == nil else { continue }
                var placeholder = MonthInfo(
                    year: year,
                    month: month,
                    totalPhotos: itemMetrics[key]?.totalPhotos ?? 0,
                    skippedCount: skippedMetrics[key] ?? 0,
                    pendingDeleteCount: itemMetrics[key]?.pendingDeleteCount ?? 0,
                    confirmedCount: confirmedMetrics[key] ?? 0
                )
                if placeholder.totalPhotos == 0 && placeholder.processedCount == 0 {
                    placeholder.status = .completed
                    placeholder.progress = 1
                }
                monthInfos[key] = placeholder
                monthComponents[key] = (year, month)
                didAdd = true
            }
        }
        if didAdd {
            publishSections()
        }
    }
}

private struct ItemMetrics: Equatable {
    let year: Int
    let month: Int
    var totalPhotos: Int
    var pendingDeleteCount: Int
}

private func diffKeys<Value: Equatable>(old: [String: Value], new: [String: Value]) -> Set<String> {
    var changed: Set<String> = []
    let keys = Set(old.keys).union(new.keys)
    for key in keys {
        if old[key] != new[key] {
            changed.insert(key)
        }
    }
    return changed
}
