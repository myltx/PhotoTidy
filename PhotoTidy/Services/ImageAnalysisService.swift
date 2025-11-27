
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

    // MARK: - 感知哈希 pHash

    /// 计算简单的 64bit 感知哈希（pHash）
    /// 算法大致步骤：
    /// 1. 将图片缩放到 32x32 灰度
    /// 2. 对 32x32 灰度图做 2D-DCT
    /// 3. 取左上 8x8 的低频系数，按中位数大小生成 64bit 位图
    func perceptualHash(for image: UIImage) -> UInt64? {
        guard let cgImage = image.cgImage else { return nil }

        let size = 32
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerPixel = 1
        let bytesPerRow = size * bytesPerPixel
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: size * size)

        guard let context = CGContext(
            data: &rawData,
            width: size,
            height: size,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // 转成 Double 矩阵做 DCT
        var pixels = [Double](repeating: 0, count: size * size)
        for i in 0..<rawData.count {
            pixels[i] = Double(rawData[i]) / 255.0
        }

        // 计算 32x32 的 2D-DCT，仅保留前 8x8 区域
        let N = size
        var dct = [Double](repeating: 0, count: 64) // 8x8

        for u in 0..<8 {
            for v in 0..<8 {
                var sum: Double = 0
                for x in 0..<N {
                    for y in 0..<N {
                        let pixel = pixels[x * N + y]
                        let cos1 = cos((Double(2 * x + 1) * Double(u) * .pi) / Double(2 * N))
                        let cos2 = cos((Double(2 * y + 1) * Double(v) * .pi) / Double(2 * N))
                        sum += pixel * cos1 * cos2
                    }
                }
                let cu: Double = (u == 0) ? (1.0 / sqrt(2.0)) : 1.0
                let cv: Double = (v == 0) ? (1.0 / sqrt(2.0)) : 1.0
                let coefficient = 2.0 / Double(N) * cu * cv * sum
                dct[u * 8 + v] = coefficient
            }
        }

        // 计算中位数（通常会去掉 DC 分量，这里保留简单实现）
        var sorted = dct
        sorted.sort()
        let median = sorted[sorted.count / 2]

        // 生成 64bit hash：系数 > 中位数 = 1，否则 = 0
        var hash: UInt64 = 0
        for (i, value) in dct.enumerated() {
            if value > median {
                hash |= (1 << UInt64(63 - i))
            }
        }
        return hash
    }

    /// 计算两个 64bit 哈希的汉明距离
    func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        var x = a ^ b
        var count = 0
        while x != 0 {
            count += 1
            x &= (x - 1) // 清掉最低位的 1
        }
        return count
    }
}
