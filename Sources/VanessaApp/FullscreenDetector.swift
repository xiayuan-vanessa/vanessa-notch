import AppKit

/// 全屏检测:判断目标屏当前是否处于其他应用的全屏空间。
/// 首选:读取该屏当前空间类型(见 isFullscreen(on:))。
/// 回退规则(无需屏幕录制权限,只读取窗口层级、所属进程与位置):
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

    /// 判定目标屏是否处于全屏空间。
    /// 优先读取该屏当前空间类型(精确);私有接口不可用或匹配不到该屏时,回退到窗口启发式。
    /// 回退原因:新版系统的全屏空间有自己的在屏菜单栏窗口,窗口启发式在其上会恒判「非全屏」。
    @MainActor
    static func isFullscreen(on screen: NSScreen) -> Bool {
        if let displays = SpaceTypeReader.managedDisplaySpaces(),
           let type = currentSpaceType(in: displays, displayID: NotchWindowController.screenID(of: screen)) {
            return type == fullscreenSpaceType
        }
        return isFullscreen(windows: currentWindows(), screenRect: cgRect(of: screen),
                            notchHeight: screen.safeAreaInsets.top,
                            ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// 空间类型:全屏(含分屏)空间为 4,普通桌面为 0。
    static let fullscreenSpaceType = 4

    /// 从 CGSCopyManagedDisplaySpaces 的结果中取出指定显示器当前空间的类型。
    /// - Parameters:
    ///   - displays: 每块显示器一项,含 "Display Identifier"(显示器 UUID)与 "Current Space"。
    ///   - displayID: 目标屏 UUID;为 nil 时只能依赖单项兜底。
    /// - Returns: 空间类型;匹配不到或字段缺失时返回 nil(交由调用方回退)。
    ///   关闭「显示器具有单独的空间」时系统只返回一项(标识为 "Main"),此时直接使用该项。
    static func currentSpaceType(in displays: [[String: Any]], displayID: String?) -> Int? {
        let entry = displays.first { ($0["Display Identifier"] as? String) == displayID }
            ?? (displays.count == 1 ? displays.first : nil)
        let current = entry?["Current Space"] as? [String: Any]
        return (current?["type"] as? NSNumber)?.intValue
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

/// 经 SkyLight 私有接口读取各显示器的空间信息。运行时 dlsym 查找符号,不参与链接;
/// 符号缺失(系统改动)时返回 nil,由 FullscreenDetector 回退到窗口启发式。
private enum SpaceTypeReader {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    /// 解析后的函数指针,只查找一次。新旧系统符号名不同(CGS* / SLS*),依次尝试。
    private static let functions: (ConnectionFn, CopySpacesFn)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let conn = dlsym(handle, "_CGSDefaultConnection") ?? dlsym(handle, "SLSMainConnectionID"),
              let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces") ?? dlsym(handle, "SLSCopyManagedDisplaySpaces")
        else {
            NSLog("[Vanessa-Notch] 未找到空间查询接口,全屏检测回退到窗口启发式")
            return nil
        }
        return (unsafeBitCast(conn, to: ConnectionFn.self), unsafeBitCast(copy, to: CopySpacesFn.self))
    }()

    /// 返回每块显示器的空间信息字典数组;接口不可用时返回 nil。
    static func managedDisplaySpaces() -> [[String: Any]]? {
        guard let (connection, copySpaces) = functions else { return nil }
        // Copy 语义:返回 +1 引用,用 takeRetainedValue 交给 ARC 释放
        return copySpaces(connection())?.takeRetainedValue() as? [[String: Any]]
    }
}
