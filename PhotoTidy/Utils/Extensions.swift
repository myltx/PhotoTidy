
import Foundation
import Photos

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Int {
    /// 字节数格式化为文件大小字符串
    var fileSizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(self))
    }
}

extension PhotoItem {
    /// 显示用的文件大小（MB）
    var fileSizeInMB: String {
        let size = Double(fileSize) / 1024.0 / 1024.0
        if size >= 1 {
            return String(format: "%.1f MB", size)
        } else {
            return String(format: "%.0f KB", Double(fileSize) / 1024.0)
        }
    }
}

extension PHAsset {
    /// 读取资源的原始文件名
    var originalFilename: String {
        PHAssetResource.assetResources(for: self).first?.originalFilename ?? "未命名"
    }
}
