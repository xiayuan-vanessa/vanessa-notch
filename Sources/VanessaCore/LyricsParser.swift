import Foundation

/// LRC + YRC 歌词解析器(纯函数,无副作用)。
public enum LyricsParser {
    /// 解析入口:有 yrc 优先用逐字,否则用 lrc。offset 标签(若有)统一应用。
    /// - Parameter tlyric: 译文 LRC(可选),按时间戳就近挂到对应行的 translation 上。
    /// - Returns: 统一歌词模型;无任何有效行时 lines 为空。
    public static func parse(lrc: String?, yrc: String?, tlyric: String? = nil) -> Lyrics {
        let offset = lrc.flatMap(parseOffset) ?? 0
        let translations = tlyric.map { parseLRC($0).map { shift($0, by: offset) } } ?? []
        if let yrc, !yrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = parseYRC(yrc)
            // 先判空再过滤:yrc 只有制作信息行时说明是纯音乐,不应回退到 lrc 再显示一遍制作信息
            if !parsed.isEmpty {
                let lines = parsed.filter { !isCreditLine($0.text) }.map { shift($0, by: offset) }
                return attachTranslations(translations, to: finalize(lines))
            }
        }
        guard let lrc else { return Lyrics(lines: []) }
        let lines = parseLRC(lrc).filter { !isCreditLine($0.text) }.map { shift($0, by: offset) }
        return attachTranslations(translations, to: finalize(lines))
    }

    /// 制作信息行的识别规则:行首为「作词 / 作曲 / 编曲…」等关键词,后接冒号。
    /// 只匹配行首,避免误伤正文中偶然出现的同名词语。
    static let creditPattern = #"^\s*(作词|作曲|编曲|词|曲|演唱|原唱|制作人|制作|监制|出品|发行|混音|录音|母带|和声|配唱|吉他|贝斯|鼓|键盘|弦乐|翻译|OP|SP|Lyricist|Lyrics|Composer|Arranger|Producer)\s*[:：∶]"#

    /// 判断一行歌词是否为制作信息(作词、作曲等),这类行不作为歌词显示。
    /// - Parameter text: 已去除时间戳的行文本。
    /// - Returns: 命中 `creditPattern`(忽略大小写)时为 true。
    static func isCreditLine(_ text: String) -> Bool {
        text.range(of: creditPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 译文与原文行起点允许的最大时间差(毫秒)。yrc 行起点与 lrc/tlyric 时间戳常有几百毫秒偏差。
    static let translationToleranceMs = 1000

    /// 把译文行挂到原文行上:每个原文行取起点最接近且差值不超过容差的非空译文行。
    /// - Parameters:
    ///   - translations: 已按起点排序、已应用 offset 的译文行。
    ///   - lyrics: finalize 后的原文歌词。
    /// - Returns: 带 translation 的歌词;无译文时原样返回。
    static func attachTranslations(_ translations: [LyricLine], to lyrics: Lyrics) -> Lyrics {
        let candidates = translations.filter { !$0.text.isEmpty }
        guard !candidates.isEmpty else { return lyrics }
        var out = lyrics
        for i in out.lines.indices where !out.lines[i].text.isEmpty {   // 空行(间奏)不挂译文
            let start = out.lines[i].startMs
            let nearest = candidates.min { abs($0.startMs - start) < abs($1.startMs - start) }
            if let nearest, abs(nearest.startMs - start) <= translationToleranceMs {
                out.lines[i].translation = nearest.text
            }
        }
        return out
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
                         words: line.words.map { Word(startMs: $0.startMs - offset, endMs: $0.endMs - offset, text: $0.text) },
                         translation: line.translation)
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
