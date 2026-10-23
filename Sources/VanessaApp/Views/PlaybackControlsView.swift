import SwiftUI

/// 悬停展开的播放控制区:歌名 · 歌手、进度条、上一首 / 播放暂停 / 下一首。
struct PlaybackControlsView: View {
    /// 面板展开时增加的高度(pt)。控制区内容约 55pt,余量用于容纳译文行等,避免挤压歌词。
    static let height: CGFloat = 64

    let display: PlayingDisplay
    var accentColor: Color
    var onCommand: (MediaCommand) -> Void

    var body: some View {
        VStack(spacing: 5) {
            Text(display.artist.isEmpty ? display.title : "\(display.title) · \(display.artist)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            progressRow
            HStack(spacing: 28) {
                button("backward.fill", .previousTrack)
                button(display.isPlaying ? "pause.fill" : "play.fill", .togglePlayPause)
                button("forward.fill", .nextTrack)
            }
        }
    }

    /// 进度行:已播时长 — 进度条 — 总时长。
    private var progressRow: some View {
        HStack(spacing: 6) {
            timeLabel(display.elapsed)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(accentColor).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)
            timeLabel(display.duration)
        }
    }

    /// 播放进度比例 0...1;总时长未知时为 0。
    private var fraction: CGFloat {
        guard display.duration > 0 else { return 0 }
        return CGFloat(min(max(display.elapsed / display.duration, 0), 1))
    }

    /// 把秒数格式化为 m:ss。
    private func timeLabel(_ seconds: Double) -> some View {
        let s = max(Int(seconds), 0)
        return Text(String(format: "%d:%02d", s / 60, s % 60))
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
    }

    /// 控制按钮:点击区域比图标略大,方便点中。
    private func button(_ symbol: String, _ command: MediaCommand) -> some View {
        Button { onCommand(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 28, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
