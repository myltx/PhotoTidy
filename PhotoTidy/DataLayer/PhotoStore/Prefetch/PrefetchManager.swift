import Foundation

enum PrefetchPriority {
    case low
    case normal
    case high
}

actor PrefetchManager {
    private var eventLog: [PhotoStoreEventLog] = []

    func record(_ description: String) {
        let entry = PhotoStoreEventLog(description: description)
        eventLog.append(entry)
        if eventLog.count > 50 {
            eventLog.removeFirst()
        }
    }

    func currentLog() -> [PhotoStoreEventLog] {
        eventLog
    }

    func prefetch(
        intent: PhotoQueryIntent,
        assets: [PhotoAssetMetadata],
        coordinator: CacheCoordinator
    ) async {
        let plan = strategy(for: intent, assets: assets)
        guard !plan.assets.isEmpty else { return }
        record("Prefetch \(plan.assets.count) for \(intent.cacheTag.rawValue) priority=\(plan.priority)")
        await coordinator.hydrate(plan.assets, tag: intent.cacheTag)
    }

    private func strategy(for intent: PhotoQueryIntent, assets: [PhotoAssetMetadata]) -> (assets: [PhotoAssetMetadata], priority: PrefetchPriority) {
        switch intent {
        case .sequential:
            return (Array(assets.prefix(3)), .high)
        case .grouped(let kind):
            let subset = kind == .similar ? assets : Array(assets.prefix(4))
            return (subset, .normal)
        case .ranked:
            return (Array(assets.prefix(8)), .normal)
        case .bucketed:
            return (Array(assets.prefix(5)), .low)
        case .pending:
            return (Array(assets.prefix(6)), .normal)
        case .dashboard:
            return ([], .low)
        }
    }
}
