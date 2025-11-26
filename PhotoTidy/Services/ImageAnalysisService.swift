
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// 简单本地图像分析：清晰度、曝光、文档检测、特征向量
final class ImageAnalysisService {
    static let shared = ImageAnalysisService()

    private let context = CIContext()

    private init() {}

    /// 计算“清晰度评分”（基于灰度方差的简单指标，值越大越清晰）
    func computeBlurScore(for image: UIImage) -> Double? {
        guard let cgImage = image.cgImage else { return nil }

        let width = 64
        let height = 64
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerPixel = 1
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let count = width * height
        if count == 0 { return nil }

        var sum: Double = 0
        var sumSq: Double = 0

        for v in rawData {
            let value = Double(v) / 255.0
            sum += value
            sumSq += value * value
        }

        let mean = sum / Double(count)
        let variance = max(sumSq / Double(count) - mean * mean, 0)
        let std = sqrt(variance)
        return std
    }

    /// 曝光是否严重异常（极亮/极暗像素占比很高）
    func isExposureBad(for image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let width = 64
        let height = 64
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerPixel = 1
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let count = width * height
        if count == 0 { return false }

        var veryBright = 0
        var veryDark = 0

        for v in rawData {
            let value = Double(v) / 255.0
            if value > 0.98 { veryBright += 1 }
            if value < 0.02 { veryDark += 1 }
        }

        let brightRatio = Double(veryBright) / Double(count)
        let darkRatio = Double(veryDark) / Double(count)
        return brightRatio > 0.8 || darkRatio > 0.8
    }

    /// 文档照片检测（利用 Vision 的矩形检测，适合票据/白板/纸质文件）
    func isDocumentLike(image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.3

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let rects = request.results ?? []
            return !rects.isEmpty
        } catch {
            return false
        }
    }

    /// 生成 Vision 特征向量（用于相似度计算）
    func featurePrint(for image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    /// 计算两个特征向量的距离（越小说明越相似）
    func distance(
        between a: VNFeaturePrintObservation,
        and b: VNFeaturePrintObservation
    ) -> Float? {
        var distance: Float = 0
        do {
            try a.computeDistance(&distance, to: b)
            return distance
        } catch {
            return nil
        }
    }
}
