import Foundation
import VanessaCore

/// QQ 音乐兜底歌词源(非公开接口):搜索候选 → SongMatcher 选歌 → 拉取 LRC(+ 译文)。
/// 只取按行的 LRC;QQ 的逐字歌词(QRC)为加密格式,不使用。
public struct QQMusicLyricsSource: FallbackLyricsSource {
    public let name = "QQ音乐"
    private let session: URLSession
    private static let headers = ["Referer": "https://y.qq.com/"]   // 接口要求带 QQ 音乐站内 Referer

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func lyrics(title: String, artist: String, durationMs: Int) async throws -> Lyrics? {
        let songs = try await search(keywords: "\(title) \(artist)".trimmingCharacters(in: .whitespaces))
            .filter { VersionFilter.isSameVersion(candidateTitle: $0.candidate.title, playingTitle: title) }
        let query = SongQuery(title: title, artist: artist, durationMs: durationMs)
        guard let best = SongMatcher.bestMatch(for: query, in: songs.map(\.candidate)),
              let mid = songs.first(where: { $0.candidate.id == best.id })?.mid else { return nil }
        let raw = try await fetchLyric(mid: mid)
        guard let lrc = raw.lyric, !lrc.isEmpty else { return nil }
        let lyrics = LyricsParser.parse(lrc: lrc, yrc: nil, tlyric: raw.trans.flatMap { $0.isEmpty ? nil : $0 })
        return lyrics.isEmpty ? nil : lyrics
    }

    /// 搜索歌曲,返回候选及其 songmid(拉歌词要用 mid,而候选 ID 用数字 songid)。
    func search(keywords: String) async throws -> [(candidate: SongCandidate, mid: String)] {
        var comps = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
        comps.queryItems = [.init(name: "w", value: keywords), .init(name: "format", value: "json"),
                            .init(name: "n", value: "10")]
        let data = try await LyricsHTTP.get(comps.url!, headers: Self.headers, session: session)
        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return decoded.data.song.list.map {
                (SongCandidate(id: $0.songid, title: $0.songname, artists: $0.singer.map(\.name),
                               durationMs: $0.interval * 1000), $0.songmid)
            }
        } catch { throw NeteaseAPIError.decoding }
    }

    /// 按 songmid 拉取歌词原文与译文(均为 LRC 文本)。
    func fetchLyric(mid: String) async throws -> LyricResponse {
        var comps = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        comps.queryItems = [.init(name: "songmid", value: mid), .init(name: "format", value: "json"),
                            .init(name: "nobase64", value: "1")]
        let data = try await LyricsHTTP.get(comps.url!, headers: Self.headers, session: session)
        do {
            return try JSONDecoder().decode(LyricResponse.self, from: data)
        } catch { throw NeteaseAPIError.decoding }
    }

    // MARK: - 解码模型(仅取需要的字段)
    private struct SearchResponse: Decodable {
        struct DataField: Decodable { let song: SongField }
        struct SongField: Decodable { let list: [Song] }
        struct Song: Decodable {
            let songid: Int64; let songmid: String; let songname: String
            let interval: Int; let singer: [Singer]
        }
        struct Singer: Decodable { let name: String }
        let data: DataField
    }
    struct LyricResponse: Decodable {
        let lyric: String?
        let trans: String?
    }
}
