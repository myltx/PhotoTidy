
import Foundation
import Photos

/// 单张照片/视频的元数据 + 分析结果
struct PhotoItem: Identifiable, Hashable {
    let id: String            // PHAsset.localIdentifier
    let asset: PHAsset

    // 基本信息
    var pixelSize: CGSize
    var fileSize: Int         // 字节
    var creationDate: Date?
    var isVideo: Bool
    var isScreenshot: Bool

    // 分析结果
    var blurScore: Double?        // 清晰度评分（越大越清晰）
    var exposureIsBad: Bool       // 曝光是否异常
    var isBlurredOrShaky: Bool    // 是否模糊/抖动
    var isDocumentLike: Bool      // 是否疑似文档照片
    var isLargeFile: Bool         // 是否大文件
    var similarGroupId: Int?      // 相似组 ID

    // UI 状态
    var markedForDeletion: Bool = false

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
