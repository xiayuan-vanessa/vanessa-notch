import SwiftUI
import VanessaCore

/// 上方方角、下方圆角的"刘海岛"形状:顶边与屏幕顶平齐,黑色与物理刘海融为一体。
struct NotchIslandShape: Shape {
    var radius: CGFloat = 20
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))                       // 左上(方角)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))                    // 右上(方角)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY),
                       control: CGPoint(x: r.maxX, y: r.maxY))          // 右下圆角
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius),
                       control: CGPoint(x: r.minX, y: r.maxY))          // 左下圆角
        p.closeSubpath()
        return p
    }
}

/// 播放面板(刘海岛):顶行封面靠左、音频条靠右,中间留出物理刘海空隙;歌词在刘海下方居中。
struct PlayingPanelView: View {
    let display: PlayingDisplay
    var fontSize: CGFloat
    var width: CGFloat
    var height: CGFloat
    var accentColor: Color = .notchAccent
    var showTranslation: Bool = true
    /// 物理刘海高度(pt);无刘海为 0。顶行至少与刘海等高,保证歌词从刘海下沿以下开始。
    var notchHeight: CGFloat = 0
    /// 歌词顶部额外间距(pt,来自设置);只下移歌词,封面与均衡器位置不变。
    var lyricTopOffset: CGFloat = 0
    /// 是否展开播放控制区(悬停触发)。
    var expanded: Bool = false
    var onCommand: (MediaCommand) -> Void = { _ in }
    /// 跳转到指定进度(秒)。
    var onSeek: (Double) -> Void = { _ in }

    /// 封面在顶行(收起)与控制区(展开)之间做共享元素过渡的命名空间。
    @Namespace private var coverNamespace

    var body: some View {
        VStack(spacing: 3) {
            // 顶行:与菜单栏/刘海等高,封面与音频条分列刘海两侧(中间留出 185pt 刘海)。
            // 展开时封面移交给控制区,借 matchedGeometryEffect 放大移动过去。
            HStack(spacing: 0) {
                if !expanded {
                    CoverView(data: display.artworkData, cornerRadius: 6).equatable()   // 仅封面数据变化时才重新解码
                        .matchedGeometryEffect(id: CoverView.matchID, in: coverNamespace)
                        .frame(width: 24, height: 24)
                }
                Spacer(minLength: 150)   // 中间空隙容纳物理刘海
                DecorativeBars(isPlaying: display.isPlaying, color: accentColor)
            }
            .frame(height: headerHeight)
            // 歌词:刘海正下方居中。换行时旧行上移淡出、新行自下淡入。
            ZStack {
                lyricBlock
                    .id(display.position.lineIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .offset(y: -6))))
            }
            .animation(.easeOut(duration: 0.25), value: display.position.lineIndex)
            .padding(.top, lyricTopOffset)
            Spacer(minLength: 0)
            if expanded {
                PlaybackControlsView(display: display, accentColor: accentColor,
                                     coverNamespace: coverNamespace, onCommand: onCommand, onSeek: onSeek)
                    .transition(.opacity)
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .frame(width: width, height: height + (expanded ? PlaybackControlsView.height : 0), alignment: .top)
        .background(islandBackground)
    }

    /// 面板背景:纯黑岛形 + 底部专辑色氛围光。
    /// 氛围光经纵向渐变遮罩只铺在下半部,顶部保持纯黑以与物理刘海融为一体;换歌时新旧颜色淡入淡出。
    private var islandBackground: some View {
        NotchIslandShape(radius: 18).fill(.black)
            .overlay {
                ZStack {
                    RadialGradient(colors: [accentColor.opacity(0.18), .clear],
                                   center: .bottom, startRadius: 0, endRadius: width * 0.55)
                        .id(accentColor)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.6), value: accentColor)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                             .init(color: .black, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .clipShape(NotchIslandShape(radius: 18))
            }
    }

    /// 顶行高度:默认 30pt;刘海更高时(如缩放为「更多空间」分辨率)加高到刘海下沿,
    /// 避免歌词顶进刘海。2 为面板顶部内边距。
    private var headerHeight: CGFloat {
        max(30, notchHeight - 2)
    }

    /// 当前行原文(逐字高亮)+ 可选译文。
    private var lyricBlock: some View {
        VStack(spacing: 2) {
            KaraokeLineView(text: display.lineText, words: display.words,
                            position: display.position, fontSize: fontSize,
                            accentColor: accentColor)
            if showTranslation, let translation = display.translation {
                Text(translation)
                    .font(.system(size: max(fontSize - 2, 9)))
                    .foregroundStyle(accentColor.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }
}

/// 封面缩略图。实现 Equatable 配合 .equatable(),避免 30fps 刷新时每帧重复解码图片。
/// 尺寸由调用方在外层 frame 决定(自身可伸缩),以便 matchedGeometryEffect 过渡时平滑缩放。
struct CoverView: View, Equatable {
    /// 顶行封面与控制区封面共享的 matchedGeometryEffect 标识。
    static let matchID = "cover"

    let data: Data?
    var cornerRadius: CGFloat

    var body: some View {
        if let data, let img = NSImage(data: data) {
            Image(nsImage: img).resizable()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
