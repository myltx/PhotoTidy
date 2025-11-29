import Foundation

/// 负责读取/写入本地清理进度的存储器（使用 UserDefaults，仅本地持久化）
final class CleanupProgressStore {
    static let shared = CleanupProgressStore()

    private let storageKey = "cleanup_progress_records"
    private let defaults: UserDefaults
    private var cache: [String: CleanupProgress]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        if
            let data = defaults.data(forKey: storageKey),
            let decoded = try? decoder.decode([String: CleanupProgress].self, from: data)
        {
            self.cache = decoded
        } else {
            self.cache = [:]
        }
    }

    func save(_ progress: CleanupProgress) {
        lock.lock()
        if progress.isMeaningful {
            cache[progress.key] = progress
        } else {
            cache.removeValue(forKey: progress.key)
        }
        persistLocked()
        lock.unlock()
    }

    func progress(year: Int, month: Int) -> CleanupProgress? {
        lock.lock()
        defer { lock.unlock() }
        return cache[Self.key(year: year, month: month)]
    }

    func allProgresses() -> [CleanupProgress] {
        lock.lock()
        let values = Array(cache.values)
        lock.unlock()
        return values
    }

    func updateProcessedCount(year: Int, month: Int, to processedCount: Int) {
        modifyProgress(year: year, month: month) { progress in
            progress.processedCount = max(processedCount, 0)
        }
    }

    func setMonthCleaned(year: Int, month: Int, cleaned: Bool) {
        modifyProgress(year: year, month: month) { progress in
            progress.isMarkedCleaned = cleaned
        }
    }

    func setPhoto(_ photoId: String, year: Int, month: Int, markedForDeletion: Bool) {
        modifyProgress(year: year, month: month) { progress in
            if markedForDeletion {
                progress.selectedPhotoIds.insert(photoId)
                progress.skippedPhotoIds.remove(photoId)
            } else {
                progress.selectedPhotoIds.remove(photoId)
            }
        }
    }

    func recordSkip(_ photoId: String, year: Int, month: Int) {
        modifyProgress(year: year, month: month) { progress in
            progress.skippedPhotoIds.insert(photoId)
            progress.selectedPhotoIds.remove(photoId)
        }
    }

    func removePhotoRecords(_ photoId: String, year: Int, month: Int) {
        modifyProgress(year: year, month: month) { progress in
            progress.selectedPhotoIds.remove(photoId)
            progress.skippedPhotoIds.remove(photoId)
        }
    }
    
    func resetAll() {
        lock.lock()
        cache.removeAll()
        defaults.removeObject(forKey: storageKey)
        lock.unlock()
    }

    private func modifyProgress(year: Int, month: Int, _ updater: (inout CleanupProgress) -> Void) {
        lock.lock()
        let key = Self.key(year: year, month: month)
        var progress = cache[key] ?? CleanupProgress(year: year, month: month)
        updater(&progress)
        if progress.isMeaningful {
            cache[key] = progress
        } else {
            cache.removeValue(forKey: key)
        }
        persistLocked()
        lock.unlock()
    }

    private func persistLocked() {
        guard let data = try? encoder.encode(cache) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func key(year: Int, month: Int) -> String {
        "\(year)-\(month)"
    }
}
