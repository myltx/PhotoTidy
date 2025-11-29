import Foundation

/// 单个资源的分析缓存（仅包含本地分析结果，不含原始照片）
struct PhotoAnalysisCacheEntry: Codable, Equatable {
    static let currentVersion: Int = 1

    let localIdentifier: String
    let fileSize: Int
    var isScreenshot: Bool
    var isDocumentLike: Bool
    var isTextImage: Bool
    var blurScore: Double?
    var isBlurredOrShaky: Bool
    var exposureIsBad: Bool
    var pHash: UInt64?
    var featurePrintData: Data?
    var similarityGroupId: Int?
    var similarityKind: String?
    var version: Int

    init(
        localIdentifier: String,
        fileSize: Int,
        isScreenshot: Bool,
        isDocumentLike: Bool,
        isTextImage: Bool,
        blurScore: Double?,
        isBlurredOrShaky: Bool,
        exposureIsBad: Bool,
        pHash: UInt64?,
        featurePrintData: Data?,
        similarityGroupId: Int?,
        similarityKind: String?
    ) {
        self.localIdentifier = localIdentifier
        self.fileSize = fileSize
        self.isScreenshot = isScreenshot
        self.isDocumentLike = isDocumentLike
        self.isTextImage = isTextImage
        self.blurScore = blurScore
        self.isBlurredOrShaky = isBlurredOrShaky
        self.exposureIsBad = exposureIsBad
        self.pHash = pHash
        self.featurePrintData = featurePrintData
        self.similarityGroupId = similarityGroupId
        self.similarityKind = similarityKind
        self.version = Self.currentVersion
    }
}
