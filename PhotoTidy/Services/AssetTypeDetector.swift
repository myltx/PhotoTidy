import Foundation
import UIKit
import Photos
import Vision
import ImageIO

/// 截图 / 文档 / 文字图片 / 普通照片 分类器
/// - 完全本地：只使用 PhotoKit + Vision，不上传任何数据
@available(iOS 16.0, *)
final class AssetTypeDetector {
    static let shared = AssetTypeDetector()

    private init() {}

    // MARK: - Public API

    /// 异步版本，方便未来在 async 上下文中调用
    func detectAssetType(asset: PHAsset, image: CGImage) async -> AssetType {
        return detectAssetTypeSync(asset: asset, image: image)
    }

    /// 同步版本：方便在现有 GCD 后台线程中直接调用
    func detectAssetTypeSync(asset: PHAsset, image: CGImage) -> AssetType {
        // 1. 截图检测：尺寸 + EXIF
        if isScreenshot(asset: asset) && !hasCameraMetadataSync(asset: asset) {
            return .screenshot
        }

        // 2. 文档检测：Vision 文档分割
        if isDocumentImage(image: image) {
            return .document
        }

        // 3. 文字密集图片：OCR 统计文字块数量
        if isTextHeavyImage(image: image) {
            return .textImage
        }

        // 4. 其它视为普通照片
        return .normalPhoto
    }

    // MARK: - Screenshot Detection

    /// 尺寸是否与设备屏幕像素匹配（允许 ±1 像素误差，包含横竖屏）
    private func isScreenshot(asset: PHAsset) -> Bool {
        let screenSize = UIScreen.main.nativeBounds.size
        let w = CGFloat(asset.pixelWidth)
        let h = CGFloat(asset.pixelHeight)
        let tol: CGFloat = 1.0

        let matchNormal =
            abs(w - screenSize.width)  <= tol &&
            abs(h - screenSize.height) <= tol

        let matchRotated =
            abs(h - screenSize.width)  <= tol &&
            abs(w - screenSize.height) <= tol

        return matchNormal || matchRotated
    }

    /// 是否存在相机相关 EXIF 元数据（有的话更像是拍照，而不是截图）
    private func hasCameraMetadataSync(asset: PHAsset) -> Bool {
        guard let properties = fetchImagePropertiesSync(for: asset) else {
            return false
        }

        // TIFF：相机厂商 / 型号
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String

        // EXIF：曝光、光圈、ISO 等
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let exposureTime = exif?[kCGImagePropertyExifExposureTime]
        let aperture = exif?[kCGImagePropertyExifFNumber]
        let iso = exif?[kCGImagePropertyExifISOSpeedRatings]

        if let make, !make.isEmpty { return true }
        if let model, !model.isEmpty { return true }
        if exposureTime != nil { return true }
        if aperture != nil { return true }
        if iso != nil { return true }

        return false
    }

    /// 同步读取 PHAsset 的图片属性（EXIF / TIFF）
    private func fetchImagePropertiesSync(for asset: PHAsset) -> [CFString: Any]? {
        let semaphore = DispatchSemaphore(value: 0)
        var properties: [CFString: Any]?

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        options.version = .current

        PHImageManager.default().requestImageDataAndOrientation(
            for: asset,
            options: options
        ) { data, _, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { return }
            properties = props
        }

        semaphore.wait()
        return properties
    }

    // MARK: - Document Detection (Vision)

    /// 文档检测：这里使用 VNDetectRectanglesRequest 作为替代，
    /// 在大多数 iOS 16+ 设备上都可用，适合票据/纸张类场景。
    private func isDocumentImage(image: CGImage) -> Bool {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.3

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            let rects = request.results ?? []
            return !rects.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Text-Heavy Image Detection (Vision OCR)

    /// 使用 OCR 统计文字块数量，判断是否为“含大量文字的图片”
    private func isTextHeavyImage(image: CGImage, minTextCount: Int = 20) -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let results = request.results else {
                return false
            }

            let textBlockCount = results.count
            if textBlockCount >= minTextCount {
                return true
            }

            // 额外统计字符数，进一步放宽判定
            let totalChars: Int = results.reduce(0) { acc, obs in
                let candidate = obs.topCandidates(1).first?.string ?? ""
                return acc + candidate.count
            }

            if textBlockCount >= 10 && totalChars > 200 {
                return true
            }

            return false
        } catch {
            return false
        }
    }
}
