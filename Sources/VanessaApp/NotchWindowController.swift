import AppKit
import SwiftUI
import CoreGraphics

/// 管理刘海处的置顶透明窗口:创建、定位、随屏幕变化重定位。
@MainActor
public final class NotchWindowController {
    private let window: NSWindow
    private let hosting: NSHostingView<AnyView>
    /// 当前内容期望尺寸(由调用方根据 idle/playing 设定)。
    public var contentSize: CGSize = CGSize(width: 230, height: 64) { didSet { reposition() } }

    /// - Parameter rootView: SwiftUI 根视图(随 AppState 变化)。
    public init(rootView: AnyView) {
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
        guard let screen = Self.targetScreen() else { return }
        let notch = Self.notchSize(of: screen)
        let frame = NotchGeometry.panelFrame(screenFrame: screen.frame,
                                             notchSize: notch, panelSize: contentSize)
        window.setFrame(frame, display: true)
    }

    /// 选定目标屏:优先带刘海的屏(safeAreaInsets.top > 0),否则用主屏。
    /// 多屏(外接非刘海屏 + 内置刘海屏)时,确保面板落在刘海屏上。
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    /// 读取屏幕刘海尺寸;无刘海返回 .zero(交由 NotchGeometry 降级)。
    static func notchSize(of screen: NSScreen) -> CGSize {
        let top = screen.safeAreaInsets.top
        guard top > 0 else { return .zero }
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth = max(0, screen.frame.width - leftWidth - rightWidth)
        return CGSize(width: notchWidth > 0 ? notchWidth : 200, height: top)
    }

    /// 注册屏幕参数变化通知,变化时重定位。
    public func observeScreenChanges() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }
}
