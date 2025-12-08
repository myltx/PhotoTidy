import Foundation

extension Int {
    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

extension DeviceStorageUsage {
    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var formattedPercentageText: String? {
        guard totalBytes > 0 else { return nil }
        return String(format: "%.0f%%", usagePercentage * 100)
    }

    var formattedUsageDetailText: String? {
        guard totalBytes > 0 else { return nil }
        return "\(formattedUsed) / \(formattedTotal)"
    }
}
