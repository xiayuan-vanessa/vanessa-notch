import Foundation

/// 纯函数同步引擎:把实时毫秒位置映射成「当前行 + 当前字进度」。
public enum LyricSyncEngine {
    /// 定位当前高亮。
    /// 规则:当前行 = 最后一个 startMs <= pos 的行(行间间隙保持上一行,直至下一行开始)。
    public static func locate(positionMs pos: Double, in lyrics: Lyrics) -> LyricPosition {
        guard !lyrics.lines.isEmpty else { return .none }
        let posI = Int(pos)
        guard posI >= lyrics.lines[0].startMs else { return .none }

        var idx = 0
        for (i, line) in lyrics.lines.enumerated() where line.startMs <= posI { idx = i }
        let line = lyrics.lines[idx]

        let lineSpan = max(line.endMs - line.startMs, 1)
        let lineProgress = clamp01(Double(posI - line.startMs) / Double(lineSpan))

        guard !line.words.isEmpty else {
            return LyricPosition(lineIndex: idx, activeWordIndex: nil, wordProgress: 0, lineProgress: lineProgress)
        }

        if posI >= line.endMs {
            return LyricPosition(lineIndex: idx, activeWordIndex: line.words.count - 1,
                                 wordProgress: 1, lineProgress: 1)
        }
        for (wi, w) in line.words.enumerated() {
            if posI < w.startMs {
                return LyricPosition(lineIndex: idx, activeWordIndex: nil, wordProgress: 0, lineProgress: lineProgress)
            }
            if posI < w.endMs {
                let span = max(w.endMs - w.startMs, 1)
                let wp = clamp01(Double(posI - w.startMs) / Double(span))
                return LyricPosition(lineIndex: idx, activeWordIndex: wi, wordProgress: wp, lineProgress: lineProgress)
            }
        }
        return LyricPosition(lineIndex: idx, activeWordIndex: line.words.count - 1,
                             wordProgress: 1, lineProgress: lineProgress)
    }

    /// 将值夹入 [0, 1] 区间。
    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}
