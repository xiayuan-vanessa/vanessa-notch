import AppKit
import SwiftUI
import CoreGraphics

/// 目标屏的刘海尺寸,随分辨率/屏幕变化更新,供视图避让物理刘海。
@MainActor
public final class NotchMetrics: ObservableObject {
    /// 刘海高度(pt);无刘海为 0。缩放分辨率不同,同一块屏的刘海 pt 高度也不同。
    @Published public var notchHeight: CGFloat = 0
    public init() {}
}

/// 管理刘海处的置顶透明窗口:创建、定位、随屏幕变化重定位。
@MainActor
public final class NotchWindowController {
    private let window: NSWindow
    private let hosting: NSHostingView<AnyView>
    /// 每次重定位时同步最新刘海尺寸。
    private let metrics: NotchMetrics
    /// 当前内容期望尺寸(由调用方根据 idle/playing 设定)。
    public var contentSize: CGSize = CGSize(width: 230, height: 64) { didSet { reposition() } }
    /// 水平微调(pt,正值向右),对应设置里的「水平微调」。
    public var horizontalOffset: CGFloat = 0 {
        didSet { if horizontalOffset != oldValue { reposition() } }
    }
    /// 用户指定的显示屏 UUID;nil 或找不到该屏(已拔出)时按默认规则选屏。
    public var preferredScreenID: String? {
        didSet { if preferredScreenID != oldValue { reposition() } }
    }

    /// - Parameters:
    ///   - rootView: SwiftUI 根视图(随 AppState 变化)。
    ///   - metrics: 刘海尺寸输出,与根视图共享同一实例。
    public init(rootView: AnyView, metrics: NotchMetrics = NotchMetrics()) {
        self.metrics = metrics
        hosting = NSHostingView(rootView: rootView)
        window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar + 1
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.contentView = hosting
        reposition()
    }

    public func show() { window.orderFrontRegardless(); reposition() }
    public func hide() { window.orderOut(nil) }

    /// 替换根视图(通常只在初始化时设置一次;高频内容更新由 SwiftUI 内部完成)。
    public func update(rootView: AnyView) {
        hosting.rootView = rootView
    }

    /// 重新定位到带刘海屏的刘海下沿、水平居中。
    public func reposition() {
        guard let screen = Self.targetScreen(preferredID: preferredScreenID) else { return }
        let notch = Self.notchSize(of: screen)
        if metrics.notchHeight != notch.height { metrics.notchHeight = notch.height }
        let frame = NotchGeometry.panelFrame(screenFrame: screen.frame,
                                             notchSize: notch, panelSize: contentSize)
        window.setFrame(frame.offsetBy(dx: horizontalOffset, dy: 0), display: true)
    }

    /// 选定目标屏:用户指定的屏优先;否则优先带刘海的屏(safeAreaInsets.top > 0),再否则用主屏。
    /// 多屏(外接非刘海屏 + 内置刘海屏)时,默认确保面板落在刘海屏上。
    static func targetScreen(preferredID: String? = nil) -> NSScreen? {
        if let preferredID,
           let screen = NSScreen.screens.first(where: { screenID(of: $0) == preferredID }) {
            return screen
        }
        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    /// 屏幕的稳定标识(显示器 UUID 字符串),重启或重新插拔后保持不变;取不到时返回 nil。
    static func screenID(of screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// 当前窗口所在的目标屏(供全屏检测等使用)。
    var currentScreen: NSScreen? { Self.targetScreen(preferredID: preferredScreenID) }

    /// 读取屏幕刘海尺寸;无刘海返回 .zero(交由 NotchGeometry 降级)。
    static func notchSize(of screen: NSScreen) -> CGSize {
        let top = screen.safeAreaInsets.top
        guard top > 0 else { return .zero }
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth = max(0, screen.frame.width - leftWidth - rightWidth)
        return CGSize(width: notchWidth > 0 ? notchWidth : 200, height: top)
    }

    /// 延迟收缩窗口（供变形动画完成后调用）。
    public func shrinkAfterDelay(_ size: CGSize, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.contentSize = size
        }
    }

    /// 注册屏幕参数变化通知,变化时重定位。
    public func observeScreenChanges() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }
}
