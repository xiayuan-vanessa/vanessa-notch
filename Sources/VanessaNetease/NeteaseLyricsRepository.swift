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
        let candidates = try await source.search(title: title, artist: artist)
        let query = SongQuery(title: title, artist: artist, durationMs: durationMs)
        guard let best = SongMatcher.bestMatch(for: query, in: candidates) else {
            return .lowConfidence
        }
        return .matched(songID: best.id, lyrics: try await lyrics(forSongID: best.id))
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
