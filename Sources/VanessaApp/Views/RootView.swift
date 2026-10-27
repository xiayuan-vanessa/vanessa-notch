import SwiftUI
import VanessaCore

/// 常驻根视图：用 MorphingNotchShape 在空闲胶囊与播放面板之间平滑变形。
/// morphProgress 驱动形状插值和内容淡入淡出；窗口尺寸由 AppDelegate 协调。
struct RootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: Settings
    /// 目标屏刘海尺寸(随分辨率变化)。
    @ObservedObject var metrics: NotchMetrics
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    /// 播放 → 空闲收缩动画完成后的窗口缩小回调。
    var onShrinkComplete: (() -> Void)?
    /// 控制区按钮发出的播放命令。
    var onCommand: (MediaCommand) -> Void = { _ in }
    /// 打开「校正歌词」窗口。
    var onCorrectLyrics: () -> Void = {}

    @State private var morphProgress: Double = 0
    /// 动画收缩期间保留的播放快照(避免 .idle 后内容立即消失)。
    @State private var displaySnapshot: PlayingDisplay?
    /// 播放控制区是否展开。
    @State private var expanded = false
    /// 悬停延迟展开任务;移出时取消。
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            // 黑色底形限高到面板高度:播放时窗口按展开高度预留,底形需随面板一起伸缩。
            MorphingNotchShape(progress: morphProgress)
                .fill(.black)
                .frame(maxHeight: panelHeight)

            if let display = currentDisplay, morphProgress > 0 {
                let accent = Color(red: display.accentR,
                                   green: display.accentG,
                                   blue: display.accentB)
                PlayingPanelView(display: display,
                                 fontSize: CGFloat(settings.fontSize),
                                 width: CGFloat(settings.panelWidth),
                                 height: CGFloat(settings.totalPanelHeight),
                                 accentColor: accent,
                                 showTranslation: settings.showTranslation,
                                 notchHeight: metrics.notchHeight,
                                 lyricTopOffset: CGFloat(settings.lyricTopOffset),
                                 expanded: expanded,
                                 onCommand: onCommand)
                    .opacity(morphProgress)
            }

            if morphProgress < 1 {
                idleContent.opacity(1 - morphProgress)
            }
        }
        // 交互区域限定在面板当前高度内:窗口下方为控制区预留的透明区域既不触发悬停,
        // 点击也会穿透到下层窗口(透明像素由系统按 alpha 放行)。
        .frame(maxWidth: .infinity, maxHeight: panelHeight, alignment: .top)
        .contentShape(MorphingNotchShape(progress: morphProgress))
        .onHover { handleHover($0) }
        .contextMenu {
            if stateKind == 2 {
                Button("歌词不对？校正…") { onCorrectLyrics() }
            }
            Button("偏好设置") { onOpenSettings() }
            Button("退出") { onQuit() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: stateKind) { newKind in
            if newKind == 2 {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    morphProgress = 1
                }
            } else {
                hoverTask?.cancel()
                expanded = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    morphProgress = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    displaySnapshot = nil
                    onShrinkComplete?()
                }
            }
        }
        .onChange(of: playingDisplay) { display in
            if let display { displaySnapshot = display }
        }
        .onAppear {
            if stateKind == 2 { morphProgress = 1 }
        }
    }

    /// 面板当前高度(含展开的控制区)。
    private var panelHeight: CGFloat {
        CGFloat(settings.totalPanelHeight) + (expanded ? PlaybackControlsView.height : 0)
    }

    /// 悬停 0.3s 后展开控制区(避免鼠标路过时误触发);移出立即收起。仅播放态生效。
    private func handleHover(_ inside: Bool) {
        hoverTask?.cancel()
        guard inside else {
            setExpanded(false)
            return
        }
        guard stateKind == 2 else { return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, stateKind == 2 else { return }
            setExpanded(true)
        }
    }

    /// 切换展开状态,仅做 SwiftUI 动画。
    /// 窗口已按展开高度预留,这里不再改窗口尺寸:改尺寸那一帧系统会先拉伸旧画面显示,造成闪烁。
    private func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            expanded = value
        }
    }

    /// 状态种类标识(0 空闲 / 1 警告 / 2 播放)，用于 onChange 仅响应种类切换。
    private var stateKind: Int {
        switch appState.ui {
        case .idle: return 0
        case .warning: return 1
        case .playing: return 2
        }
    }

    /// 从当前 UI 状态中提取 PlayingDisplay（仅 .playing 时有值）。
    private var playingDisplay: PlayingDisplay? {
        if case .playing(let d) = appState.ui { return d }
        return nil
    }

    /// 优先用实时数据，收缩动画期间用快照。
    private var currentDisplay: PlayingDisplay? {
        playingDisplay ?? displaySnapshot
    }

    @ViewBuilder private var idleContent: some View {
        switch appState.ui {
        case .warning:
            IdlePillView(isWarning: true, onTap: onOpenSettings)
        default:
            IdlePillView(isWarning: false, onTap: onOpenSettings)
        }
    }
}
