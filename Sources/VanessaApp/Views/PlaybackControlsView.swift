import SwiftUI

/// 悬停展开的播放控制区:封面 + 歌名/歌手 + 上一首 / 播放暂停 / 下一首,下方进度条。
struct PlaybackControlsView: View {
    /// 面板展开时增加的高度(pt)。控制区内容约 58pt,余量用于容纳译文行等,避免挤压歌词。
    static let height: CGFloat = 64
    /// 展开后封面边长(pt)。
    private static let coverSize: CGFloat = 40

    let display: PlayingDisplay
    var accentColor: Color
    /// 与面板顶行封面共享的过渡命名空间,让封面在收起/展开间平滑放大移动。
    var coverNamespace: Namespace.ID
    var onCommand: (MediaCommand) -> Void
    /// 拖动进度条松手后跳转,参数为目标进度(秒)。
    var onSeek: (Double) -> Void = { _ in }
    /// 是否处于完整歌词模式:是则只显示「播放/暂停 + 进度条 + 歌词按钮」紧凑一行。
    var showsLyrics: Bool = false
    /// 是否有可展示的完整歌词;没有时不显示歌词按钮。
    var lyricsAvailable: Bool = false
    /// 点击歌词按钮,切换完整歌词模式。
    var onToggleLyrics: () -> Void = {}

    /// 鼠标是否悬停在进度条上(悬停时进度条变粗)。
    @State private var hoveringProgress = false
    /// 拖动中的进度比例 0...1;nil 表示未在拖动。拖动期间进度条与时间显示跟随手指而非实际播放进度。
    @State private var dragFraction: CGFloat?

    var body: some View {
        if showsLyrics {
            // 歌词模式:歌词列表占据中部,这里只留紧凑一行;封面已回到顶行
            HStack(spacing: 4) {
                button(display.isPlaying ? "pause.fill" : "play.fill", .togglePlayPause)
                progressRow
                lyricsButton
            }
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    CoverView(data: display.artworkData, cornerRadius: 8).equatable()
                        .matchedGeometryEffect(id: CoverView.matchID, in: coverNamespace)
                        .frame(width: Self.coverSize, height: Self.coverSize)
                    songInfo
                    Spacer(minLength: 4)
                    HStack(spacing: 2) {
                        button("backward.fill", .previousTrack)
                        button(display.isPlaying ? "pause.fill" : "play.fill", .togglePlayPause)
                        button("forward.fill", .nextTrack)
                        if lyricsAvailable { lyricsButton }
                    }
                }
                progressRow
            }
        }
    }

    /// 「歌词」按钮:切换完整歌词列表;歌词模式下以主题色表示已开启。
    private var lyricsButton: some View {
        Button(action: onToggleLyrics) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 13))
                .foregroundStyle(showsLyrics ? accentColor : .white)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(ControlButtonStyle())
    }

    /// 歌名(加粗)与歌手两行,超长截断;无歌手时只显示歌名。
    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            if !display.artist.isEmpty {
                Text(display.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .lineLimit(1)
    }

    /// 进度行:已播时长 — 进度条 — 总时长。
    /// 进度条放在固定 12pt 高的槽内垂直居中(整槽可拖动,便于点中),悬停或拖动时从 3pt 变粗到 5pt 不会挤动布局。
    private var progressRow: some View {
        HStack(spacing: 6) {
            timeLabel(dragFraction.map { Double($0) * display.duration } ?? display.elapsed)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(accentColor).frame(width: geo.size.width * (dragFraction ?? fraction))
                }
                .frame(height: hoveringProgress || dragFraction != nil ? 5 : 3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(seekGesture(width: geo.size.width))
            }
            .frame(height: 12)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { hoveringProgress = hovering }
            }
            timeLabel(display.duration)
        }
    }

    /// 进度条拖动手势:按下即开始跟随(点击也算一次跳转),松手时按最终位置跳转。总时长未知时不响应。
    /// - Parameter width: 进度条可拖动区域宽度(pt)
    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard display.duration > 0, width > 0 else { return }
                dragFraction = min(max(value.location.x / width, 0), 1)
            }
            .onEnded { value in
                defer { dragFraction = nil }
                guard display.duration > 0, width > 0 else { return }
                let f = min(max(value.location.x / width, 0), 1)
                onSeek(Double(f) * display.duration)
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

    /// 控制按钮:点击区域比图标略大,方便点中;悬停显示圆形底色,按下轻微缩小。
    private func button(_ symbol: String, _ command: MediaCommand) -> some View {
        Button { onCommand(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(ControlButtonStyle())
    }
}

/// 控制按钮样式:悬停时显示浅白圆形底色,按下时缩小,提供点击反馈。
private struct ControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ControlButtonBody(configuration: configuration)
    }
}

/// ButtonStyle 本身不能持有 @State,悬停状态放在这个承载视图里。
private struct ControlButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .background(Circle().fill(.white.opacity(hovering ? 0.15 : 0)))
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}
