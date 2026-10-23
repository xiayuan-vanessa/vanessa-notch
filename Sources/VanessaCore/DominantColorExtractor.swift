import Foundation
import CoreGraphics
import ImageIO

/// 从专辑封面图片中提取主色调的工具。
/// 使用色相桶 + 饱和度加权算法，过滤低亮度和低饱和度像素，
/// 确保提取到的颜色具有视觉辨识度。
public enum DominantColorExtractor {

    /// 缩放后的采样尺寸（宽高均为此值）
    private static let sampleSize = 32

    /// 色相桶数量（360° / 30° = 12 个桶）
    private static let hueBucketCount = 12

    /// 从图片 Data 提取主色调 RGB。
    /// - Parameter imageData: 图片的原始二进制数据（支持 PNG、JPEG 等 ImageIO 可解码格式）
    /// - Returns: 归一化的 RGB 元组 (0...1)；所有像素被过滤或数据无效时返回 nil
    public static func extract(from imageData: Data) -> (r: Double, g: Double, b: Double)? {
        // 1. 解码图片数据为 CGImage
        guard let cgImage = decodeCGImage(from: imageData) else { return nil }

        // 2. 缩放到采样尺寸并读取像素
        guard let pixels = readPixels(from: cgImage) else { return nil }

        // 3. 转换为 HSB 并过滤，按色相桶累计加权
        let buckets = buildHueBuckets(from: pixels)

        // 4. 从权重最大的桶中计算加权平均 RGB
        return dominantRGB(from: buckets)
    }

    // MARK: - 图片解码

    /// 将 Data 解码为 CGImage。
    /// - Parameter data: 图片二进制数据
    /// - Returns: 解码后的 CGImage；失败返回 nil
    private static func decodeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - 像素读取

    /// 表示单个像素的 RGBA 值（归一化到 0...1）
    private struct Pixel {
        let r: Double, g: Double, b: Double
    }

    /// 将 CGImage 绘制到 32×32 的 CGContext，读取所有像素。
    /// - Parameter image: 源 CGImage
    /// - Returns: 像素数组；创建 context 失败返回 nil
    private static func readPixels(from image: CGImage) -> [Pixel]? {
        let size = sampleSize
        let bytesPerRow = size * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = ctx.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: size * size * 4)

        var pixels = [Pixel]()
        pixels.reserveCapacity(size * size)
        for i in 0..<(size * size) {
            let offset = i * 4
            let r = Double(buffer[offset]) / 255.0
            let g = Double(buffer[offset + 1]) / 255.0
            let b = Double(buffer[offset + 2]) / 255.0
            pixels.append(Pixel(r: r, g: g, b: b))
        }
        return pixels
    }

    // MARK: - 色相桶构建

    /// 色相桶：累计该桶内像素的饱和度加权 RGB 和总权重
    private struct HueBucket {
        var weightedR: Double = 0
        var weightedG: Double = 0
        var weightedB: Double = 0
        var totalWeight: Double = 0
    }

    /// 将像素转 HSB，过滤后按色相分桶，以饱和度加权累计。
    /// - Parameter pixels: 归一化的像素数组
    /// - Returns: 12 个色相桶
    private static func buildHueBuckets(from pixels: [Pixel]) -> [HueBucket] {
        var buckets = [HueBucket](repeating: HueBucket(), count: hueBucketCount)

        for px in pixels {
            let (hue, sat, bri) = rgbToHSB(r: px.r, g: px.g, b: px.b)

            // 过滤亮度 < 0.3 的像素（过暗）
            if bri < 0.3 { continue }
            // 过滤饱和度 < 0.15 的像素（接近灰白）
            if sat < 0.15 { continue }

            // 色相映射到桶索引（每 30° 一个桶）
            let bucketIndex = min(Int(hue / 30.0), hueBucketCount - 1)
            buckets[bucketIndex].weightedR += px.r * sat
            buckets[bucketIndex].weightedG += px.g * sat
            buckets[bucketIndex].weightedB += px.b * sat
            buckets[bucketIndex].totalWeight += sat
        }

        return buckets
    }

    // MARK: - 主色调提取

    /// 黑底上文字的最低感知亮度（ITU-R BT.601 加权）
    private static let minLuminance: Double = 0.5

    /// 从色相桶中取权重最大的桶，计算该桶内的加权平均 RGB。
    /// 结果保证最低感知亮度，避免在黑色刘海背景上不可见。
    /// - Parameter buckets: 12 个色相桶
    /// - Returns: 归一化 RGB；无有效桶时返回 nil
    private static func dominantRGB(from buckets: [HueBucket]) -> (r: Double, g: Double, b: Double)? {
        guard let best = buckets.max(by: { $0.totalWeight < $1.totalWeight }),
              best.totalWeight > 0 else {
            return nil
        }
        var r = best.weightedR / best.totalWeight
        var g = best.weightedG / best.totalWeight
        var b = best.weightedB / best.totalWeight

        // 用感知亮度判断（蓝色权重低，对应人眼对蓝色不敏感）
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        if lum > 0 && lum < minLuminance {
            let scale = minLuminance / lum
            r = min(r * scale, 1.0)
            g = min(g * scale, 1.0)
            b = min(b * scale, 1.0)
        }

        return (r: r, g: g, b: b)
    }

    // MARK: - RGB → HSB 转换

    /// 将归一化 RGB 转换为 HSB。
    /// - Parameters:
    ///   - r: 红色分量 (0...1)
    ///   - g: 绿色分量 (0...1)
    ///   - b: 蓝色分量 (0...1)
    /// - Returns: (hue: 0..<360, saturation: 0...1, brightness: 0...1)
    private static func rgbToHSB(r: Double, g: Double, b: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        // 亮度
        let brightness = maxC

        // 饱和度
        let saturation = maxC > 0 ? delta / maxC : 0

        // 色相
        var hue: Double = 0
        if delta > 0 {
            if maxC == r {
                hue = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxC == g {
                hue = 60.0 * (((b - r) / delta) + 2)
            } else {
                hue = 60.0 * (((r - g) / delta) + 4)
            }
            if hue < 0 { hue += 360 }
        }

        return (hue: hue, saturation: saturation, brightness: brightness)
    }
}
