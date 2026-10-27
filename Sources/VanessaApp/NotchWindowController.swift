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
    /// 可交互区域高度(pt,自窗口顶边向下),即面板当前可见部分;默认整窗可交互。
    /// 窗口其余部分是为展开 / 歌词列表预留的透明区域,鼠标在那里时窗口忽略鼠标事件,
    /// 让点击直达下层窗口或桌面(否则会挡住其他 App,台前调度也无法点桌面)。
    public var interactiveHeight: CGFloat = .greatestFiniteMagnitude {
        didSet { if interactiveHeight != oldValue { updateMousePassthrough() } }
    }
    /// 鼠标移动监听器(全局 + 本 App),随 App 生命周期常驻。
    private var mouseMonitors: [Any] = []

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
        window.acceptsMouseMovedEvents = true   // 本 App 鼠标移动监听需要窗口接收 mouseMoved
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
        updateMousePassthrough()   // 窗口位置 / 尺寸变了,可交互区域随之变化
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

    /// 开始跟踪鼠标位置,按是否位于可交互区域切换窗口的鼠标穿透。
    /// 鼠标在下层其他 App 上移动时由全局监听收到,在本窗口上移动时由本地监听收到;
    /// 监听鼠标事件不需要辅助功能权限。只需调用一次。
    public func trackMousePassthrough() {
        guard mouseMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseUp, .rightMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.updateMousePassthrough()
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    /// 鼠标在可交互区域内时接收事件,否则忽略事件(点击穿透到下层)。
    /// 按住鼠标(如拖动进度条)期间不切换,避免拖出面板时手势被中断;松开后由 mouseUp 事件补一次判断。
    private func updateMousePassthrough() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let frame = window.frame
        let height = min(interactiveHeight, frame.height)
        let interactive = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        let shouldIgnore = !interactive.contains(NSEvent.mouseLocation)
        if window.ignoresMouseEvents != shouldIgnore { window.ignoresMouseEvents = shouldIgnore }
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
