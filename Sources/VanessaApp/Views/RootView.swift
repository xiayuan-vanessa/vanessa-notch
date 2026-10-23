import SwiftUI
import VanessaCore

/// 常驻根视图：用 MorphingNotchShape 在空闲胶囊与播放面板之间平滑变形。
/// morphProgress 驱动形状插值和内容淡入淡出；窗口尺寸由 AppDelegate 协调。
struct RootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: Settings
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    /// 播放 → 空闲收缩动画完成后的窗口缩小回调。
    var onShrinkComplete: (() -> Void)?

    @State private var morphProgress: Double = 0
    /// 动画收缩期间保留的播放快照(避免 .idle 后内容立即消失)。
    @State private var displaySnapshot: PlayingDisplay?

    var body: some View {
        ZStack(alignment: .top) {
            MorphingNotchShape(progress: morphProgress)
                .fill(.black)

            if let display = currentDisplay, morphProgress > 0 {
                let accent = Color(red: display.accentR,
                                   green: display.accentG,
                                   blue: display.accentB)
                PlayingPanelView(display: display,
                                 fontSize: CGFloat(settings.fontSize),
                                 width: CGFloat(settings.panelWidth),
                                 height: CGFloat(settings.panelHeight),
                                 accentColor: accent,
                                 showTranslation: settings.showTranslation)
                    .opacity(morphProgress)
            }

            if morphProgress < 1 {
                idleContent.opacity(1 - morphProgress)
            }
        }
        .contentShape(MorphingNotchShape(progress: morphProgress))
        .contextMenu {
            Button("偏好设置") { onOpenSettings() }
            Button("退出") { onQuit() }
        }
        .onChange(of: stateKind) { newKind in
            if newKind == 2 {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    morphProgress = 1
                }
            } else {
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
