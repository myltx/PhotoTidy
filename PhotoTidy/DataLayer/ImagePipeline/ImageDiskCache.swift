import Foundation
import UIKit

/// 简单的磁盘图片缓存，采用 LRU 清理策略
final class ImageDiskCache {
    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let ioQueue = DispatchQueue(label: "ImageDiskCache.io", qos: .utility)
    private let byteLimit: UInt64

    init(
        directoryName: String = "ImagePipelineCache",
        byteLimit: UInt64 = 200 * 1_024 * 1_024
    ) {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = caches.appendingPathComponent(directoryName, isDirectory: true)
        self.byteLimit = byteLimit
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func image(forKey key: String) -> UIImage? {
        let url = directoryURL.appendingPathComponent(key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data, scale: UIScreen.main.scale)
    }

    func store(_ image: UIImage, forKey key: String) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            let url = self.directoryURL.appendingPathComponent(key)
            do {
                try data.write(to: url, options: .atomic)
                self.trimIfNeeded()
            } catch {
                // 忽略磁盘写入失败
            }
        }
    }

    func clear() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.directoryURL)
            try? self.fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        }
    }

    private func trimIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return }
        var fileInfos: [(url: URL, size: UInt64, date: Date)] = []
        var totalSize: UInt64 = 0

        for url in files {
            let attrs = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attrs[.size] as? UInt64) ?? 0
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            totalSize += size
            fileInfos.append((url, size, date))
        }

        guard totalSize > byteLimit else { return }
        let sorted = fileInfos.sorted { $0.date < $1.date }
        var remaining = totalSize

        for entry in sorted {
            guard remaining > byteLimit else { break }
            try? fileManager.removeItem(at: entry.url)
            remaining = remaining > entry.size ? remaining - entry.size : 0
        }
    }
}
