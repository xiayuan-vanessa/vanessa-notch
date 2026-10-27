import SwiftUI
import VanessaCore

/// 完整歌词列表:当前行居中高亮并随播放自动滚动跟随,点击任一行跳转到该行。
struct LyricsListView: View {
    /// 歌词模式在展开控制区的基础上额外增加的面板高度(pt)。
    static let extraHeight: CGFloat = 120

    let lines: [LyricLine]
    /// 当前行下标;进度在第一行之前时为 nil。
    let currentIndex: Int?
    var fontSize: CGFloat
    var accentColor: Color
    var showTranslation: Bool
    /// 点击某行时回调该行。
    var onSelect: (LyricLine) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        LyricsListRow(line: line, isCurrent: index == currentIndex,
                                      fontSize: fontSize, accentColor: accentColor,
                                      showTranslation: showTranslation)
                            .onTapGesture { onSelect(line) }
                            .id(index)
                    }
                }
                .padding(.vertical, 48)   // 首尾行也能滚到列表中部
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.82),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))   // 上下边缘渐隐
            .onAppear { scrollToCurrent(proxy, animated: false) }
            .onChange(of: currentIndex) { _ in scrollToCurrent(proxy, animated: true) }
        }
    }

    /// 把当前行滚动到列表中部;无当前行时滚到第一行。
    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        let target = currentIndex ?? 0
        if animated {
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .center) }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }
}

/// 歌词列表中的一行:当前行用主题色加粗,其余半透明白;悬停显示浅色底提示可点击。
private struct LyricsListRow: View {
    let line: LyricLine
    let isCurrent: Bool
    var fontSize: CGFloat
    var accentColor: Color
    var showTranslation: Bool

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 1) {
            Text(line.text)
                .font(.system(size: isCurrent ? fontSize : fontSize - 1,
                              weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? accentColor : .white.opacity(0.5))
            if showTranslation, let translation = line.translation {
                Text(translation)
                    .font(.system(size: max(fontSize - 3, 9)))
                    .foregroundStyle(isCurrent ? accentColor.opacity(0.7) : .white.opacity(0.35))
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: isCurrent)
    }
}
