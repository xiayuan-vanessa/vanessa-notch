import XCTest
import CoreGraphics
@testable import VanessaApp

final class NotchGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func test_panel_topFlushWithScreenTopCentered() {
        let notch = CGSize(width: 170, height: 34)
        let panel = CGSize(width: 230, height: 60)
        let frame = NotchGeometry.panelFrame(screenFrame: screen, notchSize: notch, panelSize: panel)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        // 顶边贴齐屏幕顶:origin.y = 屏高 - 面板高(与物理刘海融为一体)
        XCTAssertEqual(frame.origin.y, screen.height - panel.height, accuracy: 0.5)
        XCTAssertEqual(frame.width, panel.width, accuracy: 0.5)
    }

    func test_withoutNotch_topCentered() {
        let panel = CGSize(width: 230, height: 60)
        let frame = NotchGeometry.panelFrame(screenFrame: screen, notchSize: .zero, panelSize: panel)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, screen.height - panel.height, accuracy: 0.5)
    }

    func test_pillFrame_topFlushCentered() {
        let notch = CGSize(width: 170, height: 34)
        let pill = CGSize(width: 90, height: 28)
        let frame = NotchGeometry.pillFrame(screenFrame: screen, notchSize: notch, pillSize: pill)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, screen.height - pill.height, accuracy: 0.5)
    }
}
