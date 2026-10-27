import Foundation
import VanessaCore

/// 歌词查询结果。
public enum LyricsLookupResult: Equatable, Sendable {
    case matched(songID: Int64, lyrics: Lyrics)
    case lowConfidence   // 置信度不足:上层降级显示「歌名 - 歌手」
}

/// 仓储抽象,供 AppState 注入假实现测试。
public protocol LyricsRepository: Sendable {
    func lookup(title: String, artist: String, durationMs: Int) async throws -> LyricsLookupResult
    /// 按关键词搜索候选歌曲(供手动校正选歌)。
    func search(keywords: String) async throws -> [SongCandidate]
    /// 按歌曲 ID 取歌词(先缓存后网络),用于手动指定的歌曲。
    func lyrics(forSongID id: Int64) async throws -> Lyrics
}

/// 编排:搜索 → SongMatcher 选歌 → 拉歌词 → 解析 → 缓存。
public struct NeteaseLyricsRepository: LyricsRepository {
    private let source: NeteaseDataSource
    private let cache: LyricsCache

    public init(source: NeteaseDataSource, cache: LyricsCache = LyricsCache()) {
        self.source = source
        self.cache = cache
    }

    public func lookup(title: String, artist: String, durationMs: Int) async throws -> LyricsLookupResult {
        // 同一首歌再次播放时直接复用上次的匹配结果,跳过网络搜索
        let key = Self.matchKey(title: title, artist: artist, durationMs: durationMs)
        if let cachedID = cache.songID(forQuery: key) {
            return .matched(songID: cachedID, lyrics: try await lyrics(forSongID: cachedID))
        }
        let candidates = try await source.search(title: title, artist: artist)
        let query = SongQuery(title: title, artist: artist, durationMs: durationMs)
        guard let best = SongMatcher.bestMatch(for: query, in: candidates) else {
            return .lowConfidence   // 低置信度不缓存,下次播放仍会重新搜索
        }
        let lyrics = try await lyrics(forSongID: best.id)
        cache.storeSongID(best.id, forQuery: key)   // 歌词取到后再记录,避免缓存一个取不到歌词的匹配
        return .matched(songID: best.id, lyrics: lyrics)
    }

    /// 匹配缓存的查询键。时长取整到秒,吸收系统上报时长的毫秒级抖动;
    /// 时长不同(如现场版)视为不同查询。
    static func matchKey(title: String, artist: String, durationMs: Int) -> String {
        "\(title)|\(artist)|\(durationMs / 1000)"
    }

    public func search(keywords: String) async throws -> [SongCandidate] {
        try await source.search(title: keywords, artist: "")
    }

    public func lyrics(forSongID id: Int64) async throws -> Lyrics {
        if let cached = cache.lyrics(forSongID: id) {
            return cached
        }
        let raw = try await source.fetchLyrics(songID: id)
        let lyrics = LyricsParser.parse(lrc: raw.lrc, yrc: raw.yrc, tlyric: raw.tlyric)
        cache.store(lyrics, forSongID: id)
        return lyrics
    }
}
