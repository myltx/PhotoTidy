import Foundation

struct TimeMachineMonthSection: Identifiable, Equatable {
    let year: Int
    let months: [MonthInfo]

    var id: Int { year }
}

struct TimeMachineMonthMeta: Codable {
    let total: Int
    let skipped: Int
    let pending: Int
    let confirmed: Int
}
