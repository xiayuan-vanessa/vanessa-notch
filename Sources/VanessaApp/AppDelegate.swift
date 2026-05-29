import AppKit
import SwiftUI
import Combine
import VanessaCore
import VanessaNetease

/// App 装配:无 Dock 图标的菜单栏代理。创建 provider/repository/AppState,
/// 把刘海窗口内容随 AppState.ui 切换;空闲胶囊点击弹设置。
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var windowController: NotchWindowController!
    private var settings = Settings()
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var adapterAvailable = true

    /// 内嵌资源路径:bundle 内 Resources 下的 adapter 脚本与 framework。
    private func adapterPaths() -> (script: String, framework: String) {
        let res = Bundle.main.resourcePath ?? ""
        return (res + "/mediaremote-adapter.pl", res + "/MediaRemoteAdapter.framework")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = adapterPaths()
        let provider = MediaRemoteNowPlayingProvider(scriptPath: paths.script, frameworkPath: paths.framework)
        let cache = LyricsCache()
        let repository = NeteaseLyricsRepository(source: NeteaseAPIClient(), cache: cache)
        appState = AppState(provider: provider, repository: repository)
        appState.lyricLeadMs = settings.lyricOffsetMs   // 初始歌词偏移

        // 常驻根视图:观察 AppState,内容更新由 SwiftUI 内部完成,不每帧重建窗口。
        let root = RootView(appState: appState, settings: settings,
                            onOpenSettings: { [weak self] in self?.openSettings() },
                            onQuit: { NSApp.terminate(nil) })
        windowController = NotchWindowController(rootView: AnyView(root))
        windowController.contentSize = playingSize()   // 初始给播放尺寸(取自设置)
        windowController.observeScreenChanges()
        windowController.show()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusBarIcon.make()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])   // 左/右键都触发

        // 仅在「状态种类」切换时调整窗口尺寸/位置;高频歌词刷新不触发窗口变更(避免抖动)。
        cancellable = appState.$ui
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ui in
                guard let self else { return }
                self.adjustWindow(for: ui)
            }
        // 监听设置变化:若正在播放,实时同步面板宽高到窗口。
        settingsCancellable = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.appState.lyricLeadMs = self.settings.lyricOffsetMs   // 实时同步歌词偏移
                if self.lastKind == 2 { self.windowController.contentSize = self.playingSize() }
            }
        appState.start()
    }

    /// 空闲胶囊尺寸。
    private static let idleSize = CGSize(width: 140, height: 40)
    /// 播放岛尺寸:取自用户设置(下限做保护以避开物理刘海/过矮)。
    private func playingSize() -> CGSize {
        CGSize(width: max(240, settings.panelWidth), height: max(56, settings.panelHeight))
    }
    /// 上一次的状态种类(0 空闲 / 1 警告 / 2 播放),用于避免重复设尺寸。
    private var lastKind = -1

    /// 仅在状态种类变化时调整窗口尺寸(内容由 RootView 自行刷新)。
    private func adjustWindow(for ui: AppUIState) {
        let kind: Int
        let size: CGSize
        switch ui {
        case .idle:    kind = 0; size = Self.idleSize
        case .warning: kind = 1; size = Self.idleSize; adapterAvailable = false
        case .playing: kind = 2; size = playingSize()
        }
        guard kind != lastKind else { return }
        lastKind = kind
        windowController.contentSize = size   // didSet 会重新定位
    }

    /// 状态栏图标点击:左键打开设置,右键弹出「偏好设置 / 退出」菜单。
    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = makeStatusMenu()
            if let button = statusItem.button {
                menu.popUp(positioning: nil,
                           at: NSPoint(x: 0, y: button.bounds.maxY + 4),
                           in: button)
            }
        } else {
            openSettings()
        }
    }

    /// 状态栏右键菜单:与刘海面板右键菜单一致(偏好设置 / 退出)。
    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let prefs = NSMenuItem(title: "偏好设置", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// 退出 App。
    @objc private func quitApp() { NSApp.terminate(nil) }

    /// 打开设置弹窗(独立普通窗口)。
    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, adapterAvailable: adapterAvailable) {
                NSApp.terminate(nil)
            }
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.title = "Vanessa-Notch 设置"
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
