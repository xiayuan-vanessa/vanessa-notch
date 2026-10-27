import Foundation
import VanessaCore

/// 兜底歌词源:主源(网易云)取不到歌词时,按歌名 / 歌手 / 时长自行搜索并返回歌词。
public protocol FallbackLyricsSource: Sendable {
    /// 源名称,用于日志。
    var name: String { get }
    /// 查询一首歌的歌词。
    /// - Returns: 匹配到的非空歌词;没有可信匹配或该源没有带时间轴的歌词时返回 nil。
    /// - Throws: 网络或解码失败。
    func lyrics(title: String, artist: String, durationMs: Int) async throws -> Lyrics?
}

/// 多源歌词仓储:兜底缓存 → 主源 → 各兜底源依次尝试。
/// 主源匹配到非空歌词时直接采用;主源低置信度、歌词为空或出错时才查兜底源。
/// 手动校正用的 search / lyrics(forSongID:) 仍只走主源。
public struct FallbackLyricsRepository: LyricsRepository {
    private let primary: LyricsRepository
    private let sources: [FallbackLyricsSource]
    private let cache: LyricsCache

    /// - Parameters:
    ///   - primary: 主源仓储(网易云)。
    ///   - sources: 兜底源,按数组顺序依次尝试。
    ///   - cache: 用于缓存兜底源结果,同一首歌再次播放时不再请求兜底源。
    public init(primary: LyricsRepository, sources: [FallbackLyricsSource], cache: LyricsCache) {
        self.primary = primary
        self.sources = sources
        self.cache = cache
    }

    /// 查询歌词。来自兜底源的结果以 `.matched(songID: 0, …)` 返回(0 表示非网易云歌曲 ID)。
    /// - Throws: 主源出错且所有兜底源都没有结果时,抛出主源的错误(上层据此降级显示「歌名 - 歌手」)。
    public func lookup(title: String, artist: String, durationMs: Int) async throws -> LyricsLookupResult {
        let key = NeteaseLyricsRepository.matchKey(title: title, artist: artist, durationMs: durationMs)
        if let cached = cache.fallbackLyrics(forQuery: key) {
            return .matched(songID: 0, lyrics: cached)
        }
        let primaryResult: Result<LyricsLookupResult, Error>
        do {
            primaryResult = .success(try await primary.lookup(title: title, artist: artist, durationMs: durationMs))
        } catch {
            primaryResult = .failure(error)
        }
        if case .success(.matched(_, let lyrics)) = primaryResult, !lyrics.isEmpty {
            return try primaryResult.get()
        }
        if let found = await firstFallback(title: title, artist: artist, durationMs: durationMs) {
            cache.storeFallbackLyrics(found, forQuery: key)
            return .matched(songID: 0, lyrics: found)
        }
        return try primaryResult.get()   // 兜底源也没有:按主源原结果(空歌词 / 低置信度 / 错误)处理
    }

    /// 依次询问兜底源,返回第一个非空结果;单个源出错只记日志并继续尝试下一个。
    private func firstFallback(title: String, artist: String, durationMs: Int) async -> Lyrics? {
        for source in sources {
            do {
                if let lyrics = try await source.lyrics(title: title, artist: artist, durationMs: durationMs),
                   !lyrics.isEmpty {
                    return lyrics
                }
            } catch {
                NSLog("[Vanessa-Notch] 兜底歌词源 %@ 查询失败: %@", source.name, String(describing: error))
            }
        }
        return nil
    }

    public func search(keywords: String) async throws -> [SongCandidate] {
        try await primary.search(keywords: keywords)
    }

    public func lyrics(forSongID id: Int64) async throws -> Lyrics {
        try await primary.lyrics(forSongID: id)
    }
}

/// 兜底源选歌前的版本过滤。
/// SongMatcher 归一化时会去掉括号内容,「江南 (2023…演唱会武汉站)」「江南 (Live)」都会被当成「江南」;
/// 兜底源候选少,遇到时长相近的现场版 / 混音版等另一段录音就会选中,歌词时间轴整体错位。
/// 因此兜底源只保留与正在播放的标题版本一致的候选:候选带版本标记而播放标题没有时排除。
enum VersionFilter {
    /// 版本标记(小写比较)。「版」覆盖 DJ版 / 粤语版 / 鼓点版等各类改编版本。
    static let markers = ["live", "现场", "演唱会", "巡回", "remix", "混音", "dj", "伴奏",
                          "instrumental", "inst.", "纯音乐", "翻唱", "cover", "加速", "降调", "粤语", "版"]

    /// 判断候选标题与正在播放的标题是否为同一版本。
    /// - Parameters:
    ///   - candidateTitle: 兜底源候选的原始标题(未归一化)。
    ///   - playingTitle: 正在播放的标题。
    /// - Returns: 候选不含播放标题所没有的版本标记时为 true。
    static func isSameVersion(candidateTitle: String, playingTitle: String) -> Bool {
        let candidate = candidateTitle.lowercased()
        let playing = playingTitle.lowercased()
        return !markers.contains { candidate.contains($0) && !playing.contains($0) }
    }
}

/// 兜底源共用的 HTTP GET:带超时与自定义请求头,并校验状态码。
enum LyricsHTTP {
    /// 单次请求超时(秒)。兜底源依次串行尝试,单源卡住不应拖慢整条链太久。
    static let timeout: TimeInterval = 8

    /// - Parameters:
    ///   - url: 请求地址。
    ///   - headers: 额外请求头(如 Referer、User-Agent)。
    ///   - session: 注入的会话,便于测试打桩。
    /// - Returns: 响应体。
    /// - Throws: 网络错误;状态码非 2xx 时抛 `NeteaseAPIError.badStatus`。
    static func get(_ url: URL, headers: [String: String], session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await session.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NeteaseAPIError.badStatus(http.statusCode)
        }
        return data
    }
}
