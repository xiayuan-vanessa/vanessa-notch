import AppKit
import SwiftUI
import Combine
import ServiceManagement
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
    private var correctionWindow: NSWindow?
    private var provider: MediaRemoteNowPlayingProvider!
    private var adapterAvailable = true
    /// 播放控制区是否展开(展开时窗口加高)。
    private var isExpanded = false

    /// 内嵌资源路径:bundle 内 Resources 下的 adapter 脚本与 framework。
    private func adapterPaths() -> (script: String, framework: String) {
        let res = Bundle.main.resourcePath ?? ""
        return (res + "/mediaremote-adapter.pl", res + "/MediaRemoteAdapter.framework")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = adapterPaths()
        provider = MediaRemoteNowPlayingProvider(scriptPath: paths.script, frameworkPath: paths.framework)
        let cache = LyricsCache()
        let repository = NeteaseLyricsRepository(source: NeteaseAPIClient(), cache: cache)
        appState = AppState(provider: provider, repository: repository)
        appState.lyricLeadMs = settings.lyricOffsetMs   // 初始歌词偏移
        appState.pauseHideDelay = settings.pauseHideSeconds   // 初始暂停收起延时

        // 常驻根视图:用 MorphingNotchShape 变形;收缩动画结束后回调缩小窗口。
        let metrics = NotchMetrics()
        let root = RootView(appState: appState, settings: settings, metrics: metrics,
                            onOpenSettings: { [weak self] in self?.openSettings() },
                            onQuit: { NSApp.terminate(nil) },
                            onShrinkComplete: { [weak self] in
                                self?.windowController.contentSize = Self.idleSize
                            },
                            onCommand: { [weak self] in self?.provider.send($0) },
                            onExpandChange: { [weak self] in self?.setExpanded($0) },
                            onCorrectLyrics: { [weak self] in self?.openLyricsCorrection() })
        windowController = NotchWindowController(rootView: AnyView(root), metrics: metrics)
        windowController.contentSize = playingSize()   // 初始给播放尺寸(取自设置)
        windowController.horizontalOffset = CGFloat(settings.offsetX)
        windowController.preferredScreenID = settings.screenID.isEmpty ? nil : settings.screenID
        windowController.observeScreenChanges()
        loadLaunchAtLoginState()
        observeFullscreen()
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
                self.appState.pauseHideDelay = self.settings.pauseHideSeconds   // 实时同步暂停收起延时
                self.windowController.horizontalOffset = CGFloat(self.settings.offsetX)
                self.windowController.preferredScreenID = self.settings.screenID.isEmpty ? nil : self.settings.screenID
                if self.lastKind == 2 { self.windowController.contentSize = self.playingSize() }
                self.applyLaunchAtLoginIfNeeded()
                self.updateFullscreenVisibility()
            }
        appState.start()
    }

    /// 当前是否因全屏而隐藏了刘海面板。
    private var hiddenForFullscreen = false

    /// 监听空间切换与前台应用切换,刷新全屏隐藏状态。
    /// 进入/退出全屏有约 0.7s 的过渡动画,事件到达时窗口可能尚未就位,因此延迟再检查一次。
    private func observeFullscreen() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.updateFullscreenVisibility()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self?.updateFullscreenVisibility()
                }
            }
        }
    }

    /// 按「设置开关 + 目标屏是否全屏」显示或隐藏刘海面板。
    private func updateFullscreenVisibility() {
        let isFullscreen = windowController.currentScreen.map(FullscreenDetector.isFullscreen(on:)) ?? false
        let shouldHide = settings.hideInFullscreen && isFullscreen
        guard shouldHide != hiddenForFullscreen else { return }
        hiddenForFullscreen = shouldHide
        if shouldHide { windowController.hide() } else { windowController.show() }
    }

    /// 上次已应用到系统的开机启动状态,用于只在开关真正变化时调用 SMAppService。
    private var appliedLaunchAtLogin = false

    /// 启动时以系统实际登记状态回填开关(用户可能在「系统设置 → 登录项」里手动关过)。
    private func loadLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        appliedLaunchAtLogin = (status == .enabled || status == .requiresApproval)
        settings.launchAtLogin = appliedLaunchAtLogin
    }

    /// 开关变化时向系统登记/注销开机启动。
    /// 失败(如用 swift run 运行、不在 .app 包内)时记录日志,并把开关回滚为实际状态。
    private func applyLaunchAtLoginIfNeeded() {
        let wanted = settings.launchAtLogin
        guard wanted != appliedLaunchAtLogin else { return }
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            appliedLaunchAtLogin = wanted
        } catch {
            NSLog("[Vanessa-Notch] %@开机启动失败: %@", wanted ? "开启" : "关闭", String(describing: error))
            settings.launchAtLogin = appliedLaunchAtLogin
        }
    }

    /// 退出时停止歌词流并结束 adapter 子进程,避免 perl 进程在 App 退出后残留。
    public func applicationWillTerminate(_ notification: Notification) {
        appState?.stop()
    }

    /// 空闲胶囊尺寸。
    private static let idleSize = CGSize(width: 140, height: 40)
    /// 播放岛尺寸:取自用户设置(下限做保护以避开物理刘海/过矮);控制区展开时加上控制区高度。
    private func playingSize() -> CGSize {
        let extra = isExpanded ? PlaybackControlsView.height : 0
        return CGSize(width: max(240, settings.panelWidth), height: settings.totalPanelHeight + extra)
    }

    /// 控制区展开/收起:记录状态,正在播放时同步窗口尺寸。
    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        if lastKind == 2 { windowController.contentSize = playingSize() }
    }
    /// 上一次的状态种类(0 空闲 / 1 警告 / 2 播放),用于避免重复设尺寸。
    private var lastKind = -1

    /// 仅在状态种类变化时调整窗口尺寸。
    /// idle → playing：立即扩大窗口，变形动画由 RootView 驱动。
    /// playing → idle：窗口延迟收缩，等 RootView 动画完成后通过 onShrinkComplete 回调。
    private func adjustWindow(for ui: AppUIState) {
        let kind: Int
        switch ui {
        case .idle:    kind = 0
        case .warning: kind = 1; adapterAvailable = false
        case .playing: kind = 2
        }
        guard kind != lastKind else { return }
        let prevKind = lastKind
        lastKind = kind

        if kind == 2 {
            // → playing：立即扩大，动画由 RootView 驱动
            windowController.contentSize = playingSize()
        } else if prevKind == 2 {
            // playing → idle/warning：不立即收缩，等 RootView 动画结束回调
        } else {
            windowController.contentSize = Self.idleSize
        }
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
        if appState.currentSong != nil {
            let correct = NSMenuItem(title: "歌词不对？校正…", action: #selector(openLyricsCorrection), keyEquivalent: "")
            correct.target = self
            menu.addItem(correct)
        }
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

    /// 打开「校正歌词」窗口。每次打开都按当前歌曲重建内容;窗口内的操作绑定打开时的那首歌,
    /// 中途切歌也不会把偏移/选歌错记到下一首上。未在播放时不打开。
    @objc private func openLyricsCorrection() {
        guard let song = appState.currentSong else { return }
        let identity = song.identity
        let view = LyricsCorrectionView(
            title: song.title, artist: song.artist,
            offsetMs: appState.songOffset(for: identity),
            onOffsetChange: { [weak self] in self?.appState.setSongOffset($0, for: identity) },
            onSearch: { [weak self] in try await self?.appState.searchCandidates($0) ?? [] },
            onSelect: { [weak self] in try await self?.appState.applyManualMatch(songID: $0, for: identity) })
        let win = correctionWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
                                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "校正歌词"
        win.contentView = NSHostingView(rootView: view)
        win.isReleasedWhenClosed = false
        if correctionWindow == nil { win.center() }
        correctionWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
