import Foundation

/// 描述某个月份的整理状态
struct MonthStatus: Codable, Equatable {
    let totalPhotos: Int
    let predictedPendingCount: Int
    var userCleaned: Bool

    /// 是否仍需用户关注
    var needsAttention: Bool { !userCleaned && predictedPendingCount > 0 }
}
