import XCTest
import CoreGraphics
@testable import VanessaApp

final class FullscreenDetectorTests: XCTestCase {
    /// 1800×1169 的刘海屏(刘海高 38),CG 坐标原点在左上。
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    private let notch: CGFloat = 38
    private let ownPID: pid_t = 1
    private let otherPID: pid_t = 2
    private var menuLevel: Int { Int(CGWindowLevelForKey(.mainMenuWindow)) }

    private func detect(_ windows: [FullscreenDetector.WindowInfo]) -> Bool {
        FullscreenDetector.isFullscreen(windows: windows, screenRect: screen, notchHeight: notch, ownPID: ownPID)
    }

    func test_otherAppCoversScreenWithoutMenuBar_isFullscreen() {
        // 刘海屏全屏窗口让出刘海区域
        let w = FullscreenDetector.WindowInfo(layer: 0, ownerPID: otherPID,
                                              bounds: CGRect(x: 0, y: 38, width: 1800, height: 1131))
        XCTAssertTrue(detect([w]))
    }

    func test_menuBarVisible_isNotFullscreen() {
        // 隐藏程序坞后的最大化窗口同样铺满,但菜单栏仍在
        let maximized = FullscreenDetector.WindowInfo(layer: 0, ownerPID: otherPID,
                                                      bounds: CGRect(x: 0, y: 38, width: 1800, height: 1131))
        let menuBar = FullscreenDetector.WindowInfo(layer: menuLevel, ownerPID: 0,
                                                    bounds: CGRect(x: 0, y: 0, width: 1800, height: 39))
        XCTAssertFalse(detect([maximized, menuBar]))
    }

    func test_ownWindow_isIgnored() {
        let w = FullscreenDetector.WindowInfo(layer: 0, ownerPID: ownPID, bounds: screen)
        XCTAssertFalse(detect([w]))
    }

    func test_smallerWindow_isNotFullscreen() {
        let w = FullscreenDetector.WindowInfo(layer: 0, ownerPID: otherPID,
                                              bounds: CGRect(x: 100, y: 100, width: 1200, height: 800))
        XCTAssertFalse(detect([w]))
    }

    // MARK: - 空间类型解析

    private func display(_ id: String, type: Int) -> [String: Any] {
        ["Display Identifier": id, "Current Space": ["type": NSNumber(value: type)]]
    }

    func test_spaceType_matchesDisplayByID() {
        let displays = [display("AAA", type: 0), display("BBB", type: 4)]
        XCTAssertEqual(FullscreenDetector.currentSpaceType(in: displays, displayID: "BBB"), 4)
        XCTAssertEqual(FullscreenDetector.currentSpaceType(in: displays, displayID: "AAA"), 0)
    }

    func test_spaceType_singleSharedSpace_usesOnlyEntry() {
        // 关闭「显示器具有单独的空间」时只有一项,标识为 "Main"
        XCTAssertEqual(FullscreenDetector.currentSpaceType(in: [display("Main", type: 4)], displayID: "AAA"), 4)
    }

    func test_spaceType_unknownDisplayAmongMany_returnsNil() {
        let displays = [display("AAA", type: 0), display("BBB", type: 4)]
        XCTAssertNil(FullscreenDetector.currentSpaceType(in: displays, displayID: "CCC"))
        XCTAssertNil(FullscreenDetector.currentSpaceType(in: [], displayID: "AAA"))
    }

    func test_windowOnOtherScreen_isIgnored() {
        let w = FullscreenDetector.WindowInfo(layer: 0, ownerPID: otherPID,
                                              bounds: CGRect(x: 1800, y: 0, width: 2560, height: 1440))
        XCTAssertFalse(detect([w]))
    }
}
