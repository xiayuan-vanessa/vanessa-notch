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
        if let cached = cache.lyrics(forSongID: best.id) {
            return .matched(songID: best.id, lyrics: cached)
        }
        let raw = try await source.fetchLyrics(songID: best.id)
        let lyrics = LyricsParser.parse(lrc: raw.lrc, yrc: raw.yrc)
        cache.store(lyrics, forSongID: best.id)
        return .matched(songID: best.id, lyrics: lyrics)
    }
}
