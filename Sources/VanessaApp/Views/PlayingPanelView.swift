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

    var body: some View {
        VStack(spacing: 3) {
            // 顶行:与菜单栏/刘海等高,封面与音频条分列刘海两侧(中间留出 185pt 刘海)。
            HStack(spacing: 0) {
                cover
                Spacer(minLength: 150)   // 中间空隙容纳物理刘海
                DecorativeBars(isPlaying: display.isPlaying)
            }
            .frame(height: 30)
            // 歌词:刘海正下方居中。
            KaraokeLineView(text: display.lineText, words: display.words,
                            position: display.position, fontSize: fontSize)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .frame(width: width, height: height, alignment: .top)
        .background(NotchIslandShape(radius: 18).fill(.black))
    }

    @ViewBuilder private var cover: some View {
        if let data = display.artworkData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 24, height: 24)
        }
    }
}
