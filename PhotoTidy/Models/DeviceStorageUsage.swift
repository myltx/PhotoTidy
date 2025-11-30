import Foundation

/// 表示当前设备的存储使用情况，供 Dashboard 和元数据缓存使用
struct DeviceStorageUsage: Codable, Equatable {
    let totalBytes: Int64
    let freeBytes: Int64

    var usedBytes: Int64 { max(totalBytes - freeBytes, 0) }
    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var hasValidData: Bool { totalBytes > 0 }

    var formattedPercentageText: String? {
        guard hasValidData else { return nil }
        let percent = max(0, min(usagePercentage * 100, 100))
        return String(format: "%.0f%%", percent)
    }

    var formattedUsageDetailText: String? {
        guard hasValidData else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let used = formatter.string(fromByteCount: usedBytes)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(used) / \(total)"
    }

    static let empty = DeviceStorageUsage(totalBytes: 0, freeBytes: 0)

    static func current() -> DeviceStorageUsage {
        let path = NSHomeDirectory()
        guard
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
            let total = attributes[.systemSize] as? NSNumber,
            let free = attributes[.systemFreeSize] as? NSNumber
        else {
            return .empty
        }

        return DeviceStorageUsage(
            totalBytes: total.int64Value,
            freeBytes: free.int64Value
        )
    }
}
