import Foundation

/// 负责本地持久化首页智能清理进度
final class SmartCleanupProgressStore {
    private let storageKey = "smart_cleanup_progress"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    func load() -> SmartCleanupProgress? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? decoder.decode(SmartCleanupProgress.self, from: data)
    }

    func save(_ progress: SmartCleanupProgress?) {
        if let progress,
           let data = try? encoder.encode(progress) {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }
}
