import Foundation

/// IndexCatalog 负责将 PhotoStoreDatabase 的数据以模块需求形式暴露
final class IndexCatalog {
    private let database: PhotoStoreDatabase

    init(database: PhotoStoreDatabase) {
        self.database = database
    }

    func sequential(scope: PhotoScope) -> [PhotoAssetMetadata] {
        database.sequentialAssets(scope: scope)
    }

    func groups(kind: PhotoGroupKind) -> [PhotoGroupSnapshot] {
        database.groups(kind: kind)
    }

    func ranked(kind: PhotoRankedKind) -> [PhotoAssetMetadata] {
        database.rankedAssets(kind: kind)
    }

    func pending(kind: PhotoPendingKind) -> [PhotoAssetMetadata] {
        database.pendingAssets(kind: kind)
    }

    func buckets() -> [TimelineBucketSnapshot] {
        database.timelineBuckets()
    }

    func monthKeys() -> [PhotoAssetMetadata.MonthKey] {
        database.monthKeys()
    }

    func dashboard() -> DashboardSnapshot {
        database.dashboardSnapshot()
    }
}
