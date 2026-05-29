import Foundation

/// LRC + YRC 歌词解析器(纯函数,无副作用)。
public enum LyricsParser {
    /// 解析入口:有 yrc 优先用逐字,否则用 lrc。offset 标签(若有)统一应用。
    /// - Returns: 统一歌词模型;无任何有效行时 lines 为空。
    public static func parse(lrc: String?, yrc: String?) -> Lyrics {
        let offset = lrc.flatMap(parseOffset) ?? 0
        if let yrc, !yrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = parseYRC(yrc).map { shift($0, by: offset) }
            if !lines.isEmpty { return finalize(lines) }
        }
        guard let lrc else { return Lyrics(lines: []) }
        let lines = parseLRC(lrc).map { shift($0, by: offset) }
        return finalize(lines)
    }

    /// 从 [offset:xxx] 标签解析整体偏移毫秒(网易云约定:实际时间 = 标签时间 - offset)。
    static func parseOffset(_ lrc: String) -> Int? {
        guard let range = lrc.range(of: #"\[offset:\s*(-?\d+)\s*\]"#, options: .regularExpression) else { return nil }
        let token = lrc[range]
        let digits = token.filter { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    /// 解析全部 LRC 行;一行可含多个时间戳,会展开成多行。元数据/无戳行跳过。
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let stamps = timestamps(in: line)
            guard !stamps.isEmpty else { continue }
            let text = collapseSpaces(stripStamps(line))
            for ms in stamps {
                result.append(LyricLine(startMs: ms, endMs: ms, text: text, words: []))
            }
        }
        return result.sorted { $0.startMs < $1.startMs }
    }

    /// 提取一行里所有 [mm:ss.xx] / [mm:ss.xxx] 时间戳(毫秒)。元数据标签(非数字冒号格式)返回空。
    static func timestamps(in line: String) -> [Int] {
        let pattern = #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = line as NSString
        let matches = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
        return matches.map { m in
            let mm = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let ss = Int(ns.substring(with: m.range(at: 2))) ?? 0
            var frac = 0
            if m.range(at: 3).location != NSNotFound {
                let f = ns.substring(with: m.range(at: 3))
                frac = (f.count == 2) ? (Int(f) ?? 0) * 10 : (Int(f.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0)
            }
            return (mm * 60 + ss) * 1000 + frac
        }
    }

    /// 去掉行首所有 [..] 标签,保留正文。
    static func stripStamps(_ line: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\[[^\]]*\]"#) else { return line }
        let ns = line as NSString
        return re.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    /// 合并连续空白并去首尾空格。
    static func collapseSpaces(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// 整行时间平移 -offset(见 parseOffset 约定)。
    static func shift(_ line: LyricLine, by offset: Int) -> LyricLine {
        guard offset != 0 else { return line }
        return LyricLine(startMs: line.startMs - offset,
                         endMs: line.endMs - offset,
                         text: line.text,
                         words: line.words.map { Word(startMs: $0.startMs - offset, endMs: $0.endMs - offset, text: $0.text) })
    }

    /// 收尾:按起点排序,推算每行 endMs(= 下一行起点;最后一行保留自身 endMs 或 +4s 兜底)。
    static func finalize(_ lines: [LyricLine]) -> Lyrics {
        let sorted = lines.sorted { $0.startMs < $1.startMs }
        guard !sorted.isEmpty else { return Lyrics(lines: []) }
        var out = sorted
        for i in out.indices {
            if i + 1 < out.count {
                out[i].endMs = out[i + 1].startMs
            } else if out[i].endMs <= out[i].startMs {
                out[i].endMs = out[i].startMs + 4000
            }
        }
        return Lyrics(lines: out)
    }

    /// 解析 YRC 逐字歌词。行格式:`[start,duration](ws,wd,0)字(ws,wd,0)字...`。
    /// 无法识别为 yrc 行头的行直接跳过。
    static func parseYRC(_ yrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let headerRe = try? NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
        let wordRe = try? NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)([^\(\[]*)"#)
        for raw in yrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let ns = line as NSString
            guard let headerRe,
                  let head = headerRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let lineStart = Int(ns.substring(with: head.range(at: 1))) ?? 0
            let lineDur = Int(ns.substring(with: head.range(at: 2))) ?? 0
            var words: [Word] = []
            var text = ""
            if let wordRe {
                let body = ns.substring(from: head.range.length) as NSString
                for m in wordRe.matches(in: body as String, range: NSRange(location: 0, length: body.length)) {
                    let ws = Int(body.substring(with: m.range(at: 1))) ?? 0
                    let wd = Int(body.substring(with: m.range(at: 2))) ?? 0
                    let t = body.substring(with: m.range(at: 3))
                    words.append(Word(startMs: ws, endMs: ws + wd, text: t))
                    text += t
                }
            }
            if words.isEmpty { continue } // 行头有但无有效字,跳过
            result.append(LyricLine(startMs: lineStart, endMs: lineStart + lineDur,
                                    text: collapseSpaces(text), words: words))
        }
        return result
    }
}
