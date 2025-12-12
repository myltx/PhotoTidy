import Foundation

/// 全局数据容器：提供单一真相源（analysis/userState/dataController）。
/// 目前用于让主应用与 ZeroLatency 模块共享同一数据层，避免重复分析与双缓存。
@MainActor
final class PhotoDataContainer {
    static let shared = PhotoDataContainer()

    let analysisRepository: PhotoAnalysisRepository
    let userStateRepository: PhotoUserStateRepository
    let dashboardMetaStore: AnalysisDashboardMetaStore
    let dataController: PhotoDataController

    private init(
        analysisRepository: PhotoAnalysisRepository = PhotoAnalysisRepository(),
        userStateRepository: PhotoUserStateRepository = PhotoUserStateRepository(),
        dashboardMetaStore: AnalysisDashboardMetaStore = AnalysisDashboardMetaStore()
    ) {
        self.analysisRepository = analysisRepository
        self.userStateRepository = userStateRepository
        self.dashboardMetaStore = dashboardMetaStore
        self.dataController = PhotoDataController(
            analysisCache: analysisRepository,
            userStateRepo: userStateRepository,
            metaStore: dashboardMetaStore
        )
    }
}
