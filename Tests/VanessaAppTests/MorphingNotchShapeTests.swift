import XCTest
import SwiftUI
@testable import VanessaApp

final class MorphingNotchShapeTests: XCTestCase {
    /// 统一测试用的面板矩形
    private let panelRect = CGRect(x: 0, y: 0, width: 260, height: 80)

    // MARK: - progress=0 应为居中胶囊

    func test_progress0_isCenteredPill() {
        let shape = MorphingNotchShape(progress: 0)
        let path = shape.path(in: panelRect)
        let bounds = path.boundingRect

        // 宽度应接近胶囊宽度 140
        XCTAssertEqual(bounds.width, 140, accuracy: 1,
                       "progress=0 时宽度应为 140")
        // 高度应接近胶囊高度 22
        XCTAssertEqual(bounds.height, 22, accuracy: 1,
                       "progress=0 时高度应为 22")
        // 水平居中
        XCTAssertEqual(bounds.midX, panelRect.midX, accuracy: 1,
                       "progress=0 时应水平居中")
    }

    // MARK: - progress=1 应填满整个矩形

    func test_progress1_fillsRect() {
        let shape = MorphingNotchShape(progress: 1)
        let path = shape.path(in: panelRect)
        let bounds = path.boundingRect

        // 宽高应与面板矩形一致
        XCTAssertEqual(bounds.width, panelRect.width, accuracy: 1,
                       "progress=1 时宽度应填满矩形")
        XCTAssertEqual(bounds.height, panelRect.height, accuracy: 1,
                       "progress=1 时高度应填满矩形")
    }

    // MARK: - progress=0.5 应介于胶囊与面板之间

    func test_progress05_isBetween() {
        let shape = MorphingNotchShape(progress: 0.5)
        let path = shape.path(in: panelRect)
        let bounds = path.boundingRect

        // 宽度应在 (140, 260) 之间
        XCTAssertGreaterThan(bounds.width, 140,
                             "progress=0.5 时宽度应大于胶囊宽度")
        XCTAssertLessThan(bounds.width, 260,
                          "progress=0.5 时宽度应小于面板宽度")
        // 高度应在 (22, 80) 之间
        XCTAssertGreaterThan(bounds.height, 22,
                             "progress=0.5 时高度应大于胶囊高度")
        XCTAssertLessThan(bounds.height, 80,
                          "progress=0.5 时高度应小于面板高度")
    }

    // MARK: - animatableData 读写一致性

    func test_animatableData_readWrite() {
        var shape = MorphingNotchShape(progress: 0)

        // 通过 animatableData 设置值
        shape.animatableData = 0.75

        // progress 应跟着变
        XCTAssertEqual(shape.progress, 0.75, accuracy: 1e-9,
                       "设置 animatableData 后 progress 应同步更新")
        // animatableData 读回应一致
        XCTAssertEqual(shape.animatableData, 0.75, accuracy: 1e-9,
                       "animatableData 读回应与设置值一致")
    }
}
