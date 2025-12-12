import Foundation

/// 用户状态与进度的统一入口，封装 UserDefaults/本地 store。
final class PhotoUserStateRepository {
    private let timeMachineStore: TimeMachineProgressStore
    private let smartCleanupStore: SmartCleanupProgressStore
    private let skippedStore: SkippedPhotoStore

    init(
        timeMachineProgressStore: TimeMachineProgressStore = TimeMachineProgressStore(),
        smartCleanupProgressStore: SmartCleanupProgressStore = SmartCleanupProgressStore(),
        skippedPhotoStore: SkippedPhotoStore = SkippedPhotoStore()
    ) {
        self.timeMachineStore = timeMachineProgressStore
        self.smartCleanupStore = smartCleanupProgressStore
        self.skippedStore = skippedPhotoStore
    }

    // MARK: - Smart Cleanup

    func loadSmartProgress() -> SmartCleanupProgress? {
        smartCleanupStore.load()
    }

    func saveSmartProgress(_ progress: SmartCleanupProgress?) {
        smartCleanupStore.save(progress)
    }

    // MARK: - Time Machine

    func monthProgress(year: Int, month: Int) -> TimeMachineMonthProgress? {
        timeMachineStore.progress(year: year, month: month)
    }

    func allMonthProgresses() -> [TimeMachineMonthProgress] {
        timeMachineStore.allProgresses()
    }

    func setPhotoSelected(photoId: String, year: Int, month: Int, selected: Bool) {
        timeMachineStore.setPhoto(photoId, year: year, month: month, markedForDeletion: selected)
    }

    func confirmPhoto(photoId: String, year: Int, month: Int) {
        timeMachineStore.confirmPhoto(photoId, year: year, month: month)
    }

    func removePhotoRecords(photoId: String, year: Int, month: Int) {
        timeMachineStore.removePhotoRecords(photoId, year: year, month: month)
    }

    func resetAllTimeMachine() {
        timeMachineStore.resetAll()
    }

    // MARK: - Skipped Records

    func skippedRecords() -> [SkippedPhotoRecord] {
        skippedStore.allRecords()
    }

    func recordSkipped(photoId: String, source: SkippedPhotoSource) {
        skippedStore.record(photoId: photoId, source: source)
    }

    func markSkippedProcessed(ids: [String]) {
        skippedStore.markProcessed(ids: ids)
    }

    func removeSkipped(ids: [String]) {
        skippedStore.remove(ids: ids)
    }

    func clearSkipped() {
        skippedStore.clear()
    }
}

