import Foundation

/// 时光机模块使用的单个月份整理进度：仅记录待删与已确认保留的照片
struct TimeMachineMonthProgress: Codable, Equatable {
    let year: Int
    let month: Int
    var selectedPhotoIds: Set<String>
    var confirmedPhotoIds: Set<String>

    init(
        year: Int,
        month: Int,
        selectedPhotoIds: Set<String> = [],
        confirmedPhotoIds: Set<String> = []
    ) {
        self.year = year
        self.month = month
        self.selectedPhotoIds = selectedPhotoIds
        self.confirmedPhotoIds = confirmedPhotoIds
    }

    var key: String { "\(year)-\(month)" }

    var isMeaningful: Bool {
        !selectedPhotoIds.isEmpty
        || !confirmedPhotoIds.isEmpty
    }
}
