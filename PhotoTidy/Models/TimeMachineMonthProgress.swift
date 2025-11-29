import Foundation

/// 时光机模块使用的单个月份整理进度
struct TimeMachineMonthProgress: Codable, Equatable {
    let year: Int
    let month: Int
    var processedCount: Int
    var selectedPhotoIds: Set<String>
    var skippedPhotoIds: Set<String>
    var isMarkedCleaned: Bool

    init(
        year: Int,
        month: Int,
        processedCount: Int = 0,
        selectedPhotoIds: Set<String> = [],
        skippedPhotoIds: Set<String> = [],
        isMarkedCleaned: Bool = false
    ) {
        self.year = year
        self.month = month
        self.processedCount = processedCount
        self.selectedPhotoIds = selectedPhotoIds
        self.skippedPhotoIds = skippedPhotoIds
        self.isMarkedCleaned = isMarkedCleaned
    }

    var key: String { "\(year)-\(month)" }

    var isMeaningful: Bool {
        processedCount > 0
        || !selectedPhotoIds.isEmpty
        || !skippedPhotoIds.isEmpty
        || isMarkedCleaned
    }
}
