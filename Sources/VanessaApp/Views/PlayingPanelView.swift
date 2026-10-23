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

    var body: some View {
        VStack(spacing: 3) {
            // 顶行:与菜单栏/刘海等高,封面与音频条分列刘海两侧(中间留出 185pt 刘海)。
            HStack(spacing: 0) {
                CoverView(data: display.artworkData).equatable()   // 仅封面数据变化时才重新解码
                Spacer(minLength: 150)   // 中间空隙容纳物理刘海
                DecorativeBars(isPlaying: display.isPlaying)
            }
            .frame(height: 30)
            // 歌词:刘海正下方居中。换行时旧行上移淡出、新行自下淡入。
            ZStack {
                lyricBlock
                    .id(display.position.lineIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .offset(y: -6))))
            }
            .animation(.easeOut(duration: 0.25), value: display.position.lineIndex)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .frame(width: width, height: height, alignment: .top)
        .background(NotchIslandShape(radius: 18).fill(.black))
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
private struct CoverView: View, Equatable {
    let data: Data?

    var body: some View {
        if let data, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 24, height: 24)
        }
    }
}
