import SwiftUI
import VanessaCore

/// 单行逐字高亮:已唱部分亮白,未唱部分半透明;用渐变遮罩按进度推进。
struct KaraokeLineView: View {
    let text: String
    let words: [Word]
    let position: LyricPosition
    var fontSize: CGFloat = 13
    var accentColor: Color = .notchAccent

    var body: some View {
        if words.isEmpty {
            // 无逐字信息(降级文案/纯 LRC):直接以主题色显示,保持清晰。
            base.foregroundStyle(accentColor)
        } else {
            // 有逐字信息:已唱用主题色,未唱半透明,遮罩按进度从左推进。
            ZStack {
                base.foregroundStyle(accentColor.opacity(0.4))
                base.foregroundStyle(accentColor)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            highlightMask(width: geo.size.width)
                        }
                    }
                    .shadow(color: accentColor.opacity(0.5), radius: 3)   // 已唱部分轻微发光
            }
            // 不加显式动画:遮罩直接按 30fps 实时进度推进,避免滞后于歌词。
        }
    }

    /// 已唱/未唱交界处羽化过渡带的宽度(pt)。
    private static let featherWidth: CGFloat = 8

    /// 高亮遮罩:实心矩形 + 右侧由实到透明的渐变羽化带,让交界处柔和过渡而非硬切。
    /// 遮罩前沿按 progress 在 [0, width + feather] 区间推进:progress=0 时完全不亮,
    /// progress=1 时实心部分恰好覆盖整行;羽化带中点与原硬边位置的偏差不超过 feather/2。
    /// - Parameter width: 歌词文本的实际渲染宽度(pt)
    private func highlightMask(width: CGFloat) -> some View {
        let feather = Self.featherWidth
        let front = (width + feather) * CGFloat(progress)
        return HStack(spacing: 0) {
            Rectangle().frame(width: max(front - feather, 0))
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: min(front, feather))
        }
    }

    /// 超长行先缩小字号(最小 60%)以完整显示,仍放不下才截断。
    private var base: some View {
        Text(text).font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// 整行已唱比例 0...1。有逐字时按「已完成字宽 + 当前字宽 × 字内进度」/ 整行字宽计算,
    /// 让遮罩边缘落在真实字位置上(中英文混排、长短词不等宽时也不会错位);无逐字用 lineProgress。
    private var progress: Double {
        guard !words.isEmpty, let active = position.activeWordIndex, active < words.count else {
            return position.lineProgress
        }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let total = Self.width(of: words.map(\.text).joined(), font: font)
        guard total > 0 else { return position.lineProgress }
        let done = Self.width(of: words[..<active].map(\.text).joined(), font: font)
        let current = Self.width(of: words[active].text, font: font) * position.wordProgress
        return min((done + current) / total, 1)
    }

    /// 测量字符串在指定字体下的渲染宽度(pt)。缩放显示时比例不变,因此可直接用原字号测量。
    private static func width(of string: String, font: NSFont) -> Double {
        Double((string as NSString).size(withAttributes: [.font: font]).width)
    }
}
