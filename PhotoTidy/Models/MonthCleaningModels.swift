import Foundation

enum CleaningStatus: String, Codable {
    case notStarted
    case inProgress
    case completed

    var title: String {
        switch self {
        case .notStarted:
            return "未开始"
        case .inProgress:
            return "处理中"
        case .completed:
            return "已完成"
        }
    }
}

struct MonthInfo: Identifiable, Equatable {
    let year: Int
    let month: Int
    let totalPhotos: Int
    let skippedCount: Int
    let pendingDeleteCount: Int
    let confirmedCount: Int
    var status: CleaningStatus
    var progress: Double    // 0.0 ~ 1.0

    var id: String { "\(year)-\(month)" }
    var processedCount: Int { skippedCount + pendingDeleteCount + confirmedCount }

    init(
        year: Int,
        month: Int,
        totalPhotos: Int,
        skippedCount: Int,
        pendingDeleteCount: Int,
        confirmedCount: Int
    ) {
        self.year = year
        self.month = month
        self.totalPhotos = totalPhotos
        self.skippedCount = skippedCount
        self.pendingDeleteCount = pendingDeleteCount
        self.confirmedCount = confirmedCount
        let analysis = analyzeMonthCleaningStatus(
            totalPhotos: totalPhotos,
            skippedCount: skippedCount,
            pendingDeleteCount: pendingDeleteCount,
            confirmedCount: confirmedCount
        )
        self.status = analysis.status
        self.progress = analysis.progress
    }
}

@discardableResult
func analyzeMonthCleaningStatus(
    totalPhotos: Int,
    skippedCount: Int,
    pendingDeleteCount: Int,
    confirmedCount: Int
) -> (status: CleaningStatus, progress: Double) {
    let processed = max(0, skippedCount + pendingDeleteCount + confirmedCount)
    guard totalPhotos > 0 else {
        return (.notStarted, 0)
    }
    if processed <= 0 {
        return (.notStarted, 0)
    }
    if processed >= totalPhotos {
        return (.completed, 1)
    }
    let percentage = Double(processed) / Double(totalPhotos)
    return (.inProgress, min(max(percentage, 0), 1))
}
