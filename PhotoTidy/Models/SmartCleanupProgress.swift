import Foundation

/// 首页智能清理的进度记录
struct SmartCleanupProgress: Codable, Equatable {
    var lastCategoryRawValue: String
    var lastPhotoId: String?
    var hasPendingItems: Bool
    var lastUpdatedAt: Date

    init(
        lastCategoryRawValue: String = CleanupFilterMode.all.rawValue,
        lastPhotoId: String? = nil,
        hasPendingItems: Bool = false,
        lastUpdatedAt: Date = Date()
    ) {
        self.lastCategoryRawValue = lastCategoryRawValue
        self.lastPhotoId = lastPhotoId
        self.hasPendingItems = hasPendingItems
        self.lastUpdatedAt = lastUpdatedAt
    }

    var lastCategory: CleanupFilterMode {
        CleanupFilterMode(rawValue: lastCategoryRawValue) ?? .all
    }
}
