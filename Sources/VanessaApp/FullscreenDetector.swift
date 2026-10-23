import AppKit

/// 全屏检测:判断目标屏当前是否处于其他应用的全屏空间。
/// 规则(无需屏幕录制权限,只读取窗口层级、所属进程与位置):
///   1. 目标屏上看不到菜单栏窗口(全屏空间中菜单栏自动隐藏);
///   2. 且目标屏上有其他进程的普通窗口(layer 0)铺满屏幕(宽 = 屏宽,高 ≥ 屏高 - 刘海高度)。
/// 第 1 条用于排除「隐藏程序坞后的最大化窗口」这类同样铺满屏幕的情况。
/// 判定失败时倾向于「不是全屏」,即最坏情况只是不隐藏,不会误把面板藏起来。
enum FullscreenDetector {
    /// 窗口信息的最小子集,便于单测构造。
    struct WindowInfo: Equatable {
        let layer: Int
        let ownerPID: pid_t
        /// CG 全局坐标(原点在主屏左上角)。
        let bounds: CGRect
    }

    /// 纯函数判定。
    /// - Parameters:
    ///   - windows: 当前屏上可见的窗口列表。
    ///   - screenRect: 目标屏在 CG 全局坐标下的矩形。
    ///   - notchHeight: 目标屏刘海高度(无刘海为 0);刘海屏全屏窗口会让出刘海区域。
    ///   - ownPID: 本进程 PID,自己的窗口不计入。
    /// - Returns: 目标屏处于其他应用的全屏空间时返回 true。
    static func isFullscreen(windows: [WindowInfo], screenRect: CGRect,
                             notchHeight: CGFloat, ownPID: pid_t) -> Bool {
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let menuBarVisible = windows.contains { $0.layer == menuLevel && $0.bounds.intersects(screenRect) }
        guard !menuBarVisible else { return false }
        let container = screenRect.insetBy(dx: -1, dy: -1)
        return windows.contains { w in
            w.layer == 0 && w.ownerPID != ownPID
                && container.contains(w.bounds)
                && w.bounds.width >= screenRect.width - 1
                && w.bounds.height >= screenRect.height - notchHeight - 1
        }
    }

    /// 读取系统当前在屏窗口并判定目标屏是否全屏。
    static func isFullscreen(on screen: NSScreen) -> Bool {
        isFullscreen(windows: currentWindows(), screenRect: cgRect(of: screen),
                     notchHeight: screen.safeAreaInsets.top,
                     ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// NSScreen(原点左下)→ CG 全局坐标(原点在主屏左上)。
    static func cgRect(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                      width: screen.frame.width, height: screen.frame.height)
    }

    /// 读取当前在屏窗口的层级、所属进程与位置(不读取窗口标题等内容)。
    private static func currentWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return WindowInfo(layer: layer, ownerPID: pid, bounds: bounds)
        }
    }
}
