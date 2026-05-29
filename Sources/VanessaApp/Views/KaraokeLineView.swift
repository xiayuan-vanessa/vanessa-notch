import SwiftUI
import VanessaCore

/// 单行逐字高亮:已唱部分亮白,未唱部分半透明;用渐变遮罩按进度推进。
struct KaraokeLineView: View {
    let text: String
    let words: [Word]
    let position: LyricPosition
    var fontSize: CGFloat = 13

    var body: some View {
        if words.isEmpty {
            // 无逐字信息(降级文案/纯 LRC):直接以主题色显示,保持清晰。
            base.foregroundStyle(Color.notchAccent)
        } else {
            // 有逐字信息:已唱用主题色,未唱半透明,遮罩按进度从左推进。
            ZStack {
                base.foregroundStyle(Color.notchAccent.opacity(0.4))
                base.foregroundStyle(Color.notchAccent)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * CGFloat(progress))
                        }
                    }
            }
            // 不加显式动画:遮罩直接按 30fps 实时进度推进,避免滞后于歌词。
        }
    }

    private var base: some View {
        Text(text).font(.system(size: fontSize, weight: .semibold)).lineLimit(1)
    }

    /// 整行已唱比例 0...1。有逐字用「已完成字 + 当前字进度」,无逐字用 lineProgress。
    private var progress: Double {
        guard !words.isEmpty, let active = position.activeWordIndex else {
            return position.lineProgress
        }
        let total = max(words.count, 1)
        return (Double(active) + position.wordProgress) / Double(total)
    }
}
