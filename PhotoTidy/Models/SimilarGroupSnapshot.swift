import Foundation

struct SimilarGroupSnapshot: Codable, Identifiable, Hashable {
    let groupId: Int
    let assetIds: [String]
    let recommendedAssetId: String
    let latestDate: Date
    let updatedAt: Date

    var id: Int { groupId }
}
