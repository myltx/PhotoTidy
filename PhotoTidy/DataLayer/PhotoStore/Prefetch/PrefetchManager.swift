import Foundation
import CoreGraphics

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
        await coordinator.warmThumbnails(for: plan.assets, targetSize: plan.thumbnailSize)
    }

    private struct PrefetchPlan {
        let assets: [PhotoAssetMetadata]
        let priority: PrefetchPriority
        let thumbnailSize: CGSize
    }

    private func strategy(for intent: PhotoQueryIntent, assets: [PhotoAssetMetadata]) -> PrefetchPlan {
        switch intent {
        case .sequential:
            return PrefetchPlan(assets: Array(assets.prefix(3)), priority: .high, thumbnailSize: CGSize(width: 600, height: 600))
        case .grouped(let kind):
            let subset = kind == .similar ? assets : Array(assets.prefix(4))
            return PrefetchPlan(assets: subset, priority: .normal, thumbnailSize: CGSize(width: 420, height: 420))
        case .ranked:
            return PrefetchPlan(assets: Array(assets.prefix(8)), priority: .normal, thumbnailSize: CGSize(width: 320, height: 320))
        case .bucketed:
            return PrefetchPlan(assets: Array(assets.prefix(5)), priority: .low, thumbnailSize: CGSize(width: 260, height: 260))
        case .pending:
            return PrefetchPlan(assets: Array(assets.prefix(6)), priority: .normal, thumbnailSize: CGSize(width: 320, height: 320))
        case .dashboard:
            return PrefetchPlan(assets: [], priority: .low, thumbnailSize: CGSize(width: 200, height: 200))
        }
    }
}
