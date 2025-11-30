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
    private let yearCacheKey = "time_machine_available_years"

    private var itemMetrics: [String: ItemMetrics] = [:]
    private var skippedMetrics: [String: Int] = [:]
    private var confirmedMetrics: [String: Int] = [:]
    private var assetTotals: [String: Int] = [:]
    private var monthInfos: [String: MonthInfo] = [:]
    private var monthComponents: [String: (year: Int, month: Int)] = [:]
    private var photoDates: [String: Date] = [:]
    private var cachedSkippedRecords: [SkippedPhotoRecord] = []
    private var availableYears: [Int] = []

    init(dataSource: PhotoCleanupViewModel) {
        self.dataSource = dataSource
        loadCachedYears()
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

        dataSource.$monthAssetTotals
            .receive(on: processingQueue)
            .sink { [weak self] totals in
                self?.handleAssetTotals(totals)
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
        log("handleItemsUpdate items=\(items.count) changedKeys=\(changedKeys.count) years=\(availableYears)")
    }

    private func handleSkippedRecords(_ records: [SkippedPhotoRecord], cacheRecords: Bool) {
        if cacheRecords {
            cachedSkippedRecords = records
        }
        let newMetrics = buildSkippedMetrics(from: records)
        let changedKeys = diffKeys(old: skippedMetrics, new: newMetrics)
        skippedMetrics = newMetrics
        refreshMonthInfos(for: changedKeys)
        log("handleSkippedRecords records=\(records.count) changedKeys=\(changedKeys.count)")
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
        log("handleSnapshotUpdate snapshots=\(snapshots.count) changedKeys=\(changedKeys.count)")
    }

    private func rebuildSkippedMetricsFromCache() {
        guard !cachedSkippedRecords.isEmpty else { return }
        let newMetrics = buildSkippedMetrics(from: cachedSkippedRecords)
        let changedKeys = diffKeys(old: skippedMetrics, new: newMetrics)
        guard !changedKeys.isEmpty else { return }
        skippedMetrics = newMetrics
        refreshMonthInfos(for: changedKeys)
        log("rebuildSkippedMetricsFromCache changedKeys=\(changedKeys.count)")
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
            let total = assetTotals[key] ?? itemMetrics[key]?.totalPhotos ?? 0
            let pending = itemMetrics[key]?.pendingDeleteCount ?? 0
            let skipped = skippedMetrics[key] ?? 0
            let confirmed = confirmedMetrics[key] ?? 0

            let hasMetricsSource = itemMetrics[key] != nil
                || skippedMetrics[key] != nil
                || confirmedMetrics[key] != nil
                || assetTotals[key] != nil
            if !hasMetricsSource {
                if let comps = monthComponents[key] ?? components(fromKeyString: key) {
                    let placeholder = MonthInfo(
                        year: comps.year,
                        month: comps.month,
                        totalPhotos: 0,
                        skippedCount: 0,
                        pendingDeleteCount: 0,
                        confirmedCount: 0
                    )
                    if monthInfos[key] != placeholder {
                        monthInfos[key] = placeholder
                        changed = true
                    }
                }
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
        log("refreshMonthInfos processedKeys=\(keys.count) changed=\(changed)")
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
            self?.log("publishSections count=\(builtSections.count)")
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
        let years = Set(items.compactMap { item -> Int? in
            guard let date = item.creationDate else { return nil }
            return calendar.component(.year, from: date)
        })
        if !years.isEmpty {
            mergeAvailableYears(with: years)
        } else {
            ensureYearRangeFromLibraryIfNeeded()
        }
        log("ensureYearRangeFromItems years=\(years.sorted())")
    }

    private func ensureYearRangeFromLibraryIfNeeded() {
        guard availableYears.isEmpty else { return }
        if let years = fetchYearsFromLibrary() {
            mergeAvailableYears(with: Set(years))
            log("ensureYearRangeFromLibrary -> \(years)")
        }
    }

    private func ensureYearRangeFromTotals(_ keys: Set<String>) {
        let years = Set(keys.compactMap { components(fromKeyString: $0)?.year })
        guard !years.isEmpty else { return }
        mergeAvailableYears(with: years)
    }
    
    private func fetchYearsFromLibrary() -> [Int]? {
        let ascending = PHFetchOptions()
        ascending.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        ascending.fetchLimit = 1
        guard let oldest = PHAsset.fetchAssets(with: ascending).firstObject?.creationDate else {
            return nil
        }
        let descending = PHFetchOptions()
        descending.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        descending.fetchLimit = 1
        guard let newest = PHAsset.fetchAssets(with: descending).firstObject?.creationDate else {
            return nil
        }
        let minYear = calendar.component(.year, from: oldest)
        let maxYear = calendar.component(.year, from: newest)
        guard minYear <= maxYear else { return nil }

        var years: [Int] = []
        for year in stride(from: maxYear, through: minYear, by: -1) {
            if hasAsset(in: year) {
                years.append(year)
            }
        }
        return years.isEmpty ? nil : years
    }

    private func hasAsset(in year: Int) -> Bool {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        var endComponents = DateComponents()
        endComponents.year = year + 1
        endComponents.month = 1
        endComponents.day = 1
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else {
            return false
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startDate as NSDate, endDate as NSDate)
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: options).firstObject != nil
    }

    private func mergeAvailableYears(with years: Set<Int>) {
        guard !years.isEmpty else { return }
        let combined = Set(availableYears).union(years)
        let sorted = combined.sorted(by: >)
        guard sorted != availableYears else { return }
        availableYears = sorted
        cacheAvailableYears()
        ensurePlaceholdersForAvailableYears()
        log("mergeAvailableYears -> \(availableYears)")
    }

    private func loadCachedYears() {
        if let cached = UserDefaults.standard.array(forKey: yearCacheKey) as? [Int], !cached.isEmpty {
            availableYears = cached
            ensurePlaceholdersForAvailableYears()
            log("loadCachedYears -> \(cached)")
        }
    }

    private func cacheAvailableYears() {
        if availableYears.isEmpty {
            UserDefaults.standard.removeObject(forKey: yearCacheKey)
        } else {
            UserDefaults.standard.set(availableYears, forKey: yearCacheKey)
        }
    }

    private func ensurePlaceholdersForAvailableYears() {
        guard !availableYears.isEmpty else { return }
        var changed = false
        for year in availableYears {
            for month in 1...12 {
                let key = monthKey(year: year, month: month)
                guard monthInfos[key] == nil else { continue }
                let info = MonthInfo(
                    year: year,
                    month: month,
                    totalPhotos: assetTotals[key] ?? itemMetrics[key]?.totalPhotos ?? 0,
                    skippedCount: skippedMetrics[key] ?? 0,
                    pendingDeleteCount: itemMetrics[key]?.pendingDeleteCount ?? 0,
                    confirmedCount: confirmedMetrics[key] ?? 0
                )
                monthInfos[key] = info
                monthComponents[key] = (year, month)
                changed = true
            }
        }
        if changed {
            publishSections()
        }
        log("ensurePlaceholdersForAvailableYears changed=\(changed)")
    }

    private func handleAssetTotals(_ totals: [String: Int]) {
        assetTotals = totals
        let keys = Set(totals.keys)
        ensureYearRangeFromTotals(keys)
        refreshMonthInfos(for: keys)
        log("handleAssetTotals keys=\(keys.count)")
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

extension TimeMachineTimelineViewModel {
    #if DEBUG
    fileprivate func log(_ message: String) {
        print("[TimeMachineTimeline] \(message)")
    }
    #else
    fileprivate func log(_ message: String) {}
    #endif
}
