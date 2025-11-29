import Foundation

final class SkippedPhotoStore {
    private let storageKey = "skipped_photo_records"
    private let defaults: UserDefaults
    private var cache: [String: SkippedPhotoRecord]
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        if
            let data = defaults.data(forKey: storageKey),
            let decoded = try? decoder.decode([String: SkippedPhotoRecord].self, from: data)
        {
            self.cache = decoded
        } else {
            self.cache = [:]
        }
    }
    
    func allRecords() -> [SkippedPhotoRecord] {
        lock.lock()
        let values = Array(cache.values)
        lock.unlock()
        return values.sorted { $0.timestamp > $1.timestamp }
    }
    
    func record(photoId: String, source: SkippedPhotoSource) {
        lock.lock()
        var record = cache[photoId] ?? SkippedPhotoRecord(photoId: photoId, timestamp: Date(), source: source, isProcessed: false)
        record.source = source
        record.timestamp = Date()
        record.isProcessed = false
        cache[photoId] = record
        persistLocked()
        lock.unlock()
    }
    
    func markProcessed(ids: [String]) {
        guard !ids.isEmpty else { return }
        lock.lock()
        for id in ids {
            if var record = cache[id] {
                record.isProcessed = true
                cache[id] = record
            }
        }
        persistLocked()
        lock.unlock()
    }
    
    func remove(ids: [String]) {
        guard !ids.isEmpty else { return }
        lock.lock()
        for id in ids {
            cache.removeValue(forKey: id)
        }
        persistLocked()
        lock.unlock()
    }
    
    func clear() {
        lock.lock()
        cache.removeAll()
        persistLocked()
        lock.unlock()
    }
    
    private func persistLocked() {
        if let data = try? encoder.encode(cache) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
