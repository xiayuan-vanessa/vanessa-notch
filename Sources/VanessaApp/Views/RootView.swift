import SwiftUI

/// 常驻根视图:观察 AppState,按当前 UI 状态切换内容。
/// 歌词等高频更新通过 SwiftUI 内部刷新完成,窗口本身不每帧重建(避免抖动)。
struct RootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: Settings
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        // 内容顶对齐:岛形面板始终贴在窗口顶部(= 屏幕顶/刘海处)。
        VStack(spacing: 0) {
            content
                // 右键菜单:偏好设置 / 退出。
                .contextMenu {
                    Button("偏好设置") { onOpenSettings() }
                    Button("退出") { onQuit() }
                }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var content: some View {
        switch appState.ui {
        case .idle:
            IdlePillView(isWarning: false, onTap: onOpenSettings)
        case .warning:
            IdlePillView(isWarning: true, onTap: onOpenSettings)
        case .playing(let display):
            PlayingPanelView(display: display, fontSize: CGFloat(settings.fontSize),
                             width: CGFloat(settings.panelWidth), height: CGFloat(settings.panelHeight))
        }
    }
}
