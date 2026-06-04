import XCTest
import CoreGraphics
import ImageIO
@testable import VanessaCore

final class DominantColorExtractorTests: XCTestCase {

    // MARK: - 辅助方法

    /// 生成指定颜色的 4×4 纯色 PNG 图片 Data。
    /// - Parameters:
    ///   - r: 红色分量 (0...1)
    ///   - g: 绿色分量 (0...1)
    ///   - b: 蓝色分量 (0...1)
    /// - Returns: PNG 格式的 Data；生成失败则触发测试失败。
    private func makeSolidColorPNG(r: Double, g: Double, b: Double) -> Data {
        let width = 4, height = 4
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            XCTFail("无法创建 CGContext")
            return Data()
        }

        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = ctx.makeImage() else {
            XCTFail("无法生成 CGImage")
            return Data()
        }

        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData as CFMutableData, "public.png" as CFString, 1, nil
        ) else {
            XCTFail("无法创建 CGImageDestination")
            return Data()
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            XCTFail("PNG 编码失败")
            return Data()
        }
        return mutableData as Data
    }

    // MARK: - 测试用例

    /// 纯红图 → 应提取到红色主色调
    func test_solidRed_extractsRed() {
        let data = makeSolidColorPNG(r: 1, g: 0, b: 0)
        guard let result = DominantColorExtractor.extract(from: data) else {
            XCTFail("纯红图不应返回 nil")
            return
        }
        XCTAssertGreaterThan(result.r, 0.7, "红色分量应 > 0.7")
        XCTAssertLessThan(result.g, 0.4, "绿色分量应 < 0.4")
        XCTAssertLessThan(result.b, 0.4, "蓝色分量应 < 0.4")
    }

    /// 纯黑图 → 亮度过低应被过滤，返回 nil
    func test_solidBlack_returnsNil() {
        let data = makeSolidColorPNG(r: 0, g: 0, b: 0)
        XCTAssertNil(DominantColorExtractor.extract(from: data), "纯黑图应返回 nil")
    }

    /// 垃圾字节 → 无法解码，返回 nil
    func test_invalidData_returnsNil() {
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF])
        XCTAssertNil(DominantColorExtractor.extract(from: garbage), "无效数据应返回 nil")
    }

    /// 纯灰图 → 饱和度过低应被过滤，返回 nil
    func test_solidGray_returnsNil() {
        let data = makeSolidColorPNG(r: 0.5, g: 0.5, b: 0.5)
        XCTAssertNil(DominantColorExtractor.extract(from: data), "纯灰图应返回 nil")
    }

    /// 纯蓝图 → 应提取到蓝色主色调
    func test_solidBlue_extractsBlue() {
        let data = makeSolidColorPNG(r: 0, g: 0, b: 1)
        guard let result = DominantColorExtractor.extract(from: data) else {
            XCTFail("纯蓝图不应返回 nil")
            return
        }
        XCTAssertGreaterThan(result.b, 0.6, "蓝色分量应 > 0.6")
        XCTAssertLessThan(result.r, 0.3, "红色分量应 < 0.3")
    }
}
