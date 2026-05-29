import Foundation

/// 搜索接口返回的候选歌曲(已抽取成与网络无关的纯模型)。
public struct SongCandidate: Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let artists: [String]
    public let durationMs: Int
    public init(id: Int64, title: String, artists: [String], durationMs: Int) {
        self.id = id; self.title = title; self.artists = artists; self.durationMs = durationMs
    }
}

/// 选歌查询条件(来自 NowPlaying)。
public struct SongQuery: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let durationMs: Int
    public init(title: String, artist: String, durationMs: Int) {
        self.title = title; self.artist = artist; self.durationMs = durationMs
    }
}

/// 纯函数选歌器:综合标题/歌手相似度与时长接近度打分,低置信度返回 nil。
public enum SongMatcher {
    /// 选出最匹配候选。
    /// - Parameter durationToleranceMs: 时长容差;超过容差的候选时长得分归零(但不直接淘汰,标题歌手极像仍可能入选)。
    /// - Returns: 最高分候选;若最高分 < 0.5 或时长差超容差,返回 nil(交由上层降级显示「歌名-歌手」)。
    public static func bestMatch(for query: SongQuery, in candidates: [SongCandidate],
                                 durationToleranceMs: Int = 5000) -> SongCandidate? {
        let qTitle = normalize(query.title)
        let qArtist = normalize(query.artist)
        var best: (cand: SongCandidate, score: Double, durOK: Bool)?
        for c in candidates {
            let titleSim = similarity(qTitle, normalize(c.title))
            let artistSim = c.artists.map { similarity(qArtist, normalize($0)) }.max() ?? 0
            let durDiff = abs(c.durationMs - query.durationMs)
            let durOK = durDiff <= durationToleranceMs
            let durSim = durOK ? (1 - Double(durDiff) / Double(max(durationToleranceMs, 1))) : 0
            let score = 0.6 * titleSim + 0.25 * artistSim + 0.15 * durSim
            if best == nil || score > best!.score { best = (c, score, durOK) }
        }
        guard let b = best, b.score >= 0.5, b.durOK else { return nil }
        return b.cand
    }

    /// 归一化:小写、去括号内容、去 feat. 之后、去非字母数字(保留中日韩)、压空格。
    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        t = t.replacingOccurrences(of: #"[\(\（\[].*?[\)\）\]]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(feat\.?|ft\.?|featuring).*$"#, with: "", options: [.regularExpression])
        t = t.replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
        return t
    }

    /// 归一化 Levenshtein 相似度,0...1。
    static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1 }
        return 1 - Double(levenshtein(Array(a), Array(b))) / Double(maxLen)
    }

    /// 标准编辑距离(动态规划,滚动数组)。
    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
