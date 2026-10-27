import Foundation
import VanessaCore

/// LRCLIB 兜底歌词源(公开免费接口 lrclib.net):一次搜索即返回候选及其同步歌词,
/// 只在带时间轴歌词(syncedLyrics)的候选中用 SongMatcher 选歌。英文 / 日文歌覆盖较好。
public struct LRCLIBLyricsSource: FallbackLyricsSource {
    public let name = "LRCLIB"
    private let session: URLSession
    /// LRCLIB 要求请求带可识别的 User-Agent。
    private static let headers = ["User-Agent": "Vanessa-Notch (macOS notch lyrics)"]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func lyrics(title: String, artist: String, durationMs: Int) async throws -> Lyrics? {
        let tracks = try await search(title: title, artist: artist).filter {
            !$0.instrumental && !($0.syncedLyrics ?? "").isEmpty
                && VersionFilter.isSameVersion(candidateTitle: $0.trackName, playingTitle: title)
        }
        let candidates = tracks.map {
            SongCandidate(id: $0.id, title: $0.trackName, artists: [$0.artistName],
                          durationMs: Int(($0.duration ?? 0) * 1000))
        }
        let query = SongQuery(title: title, artist: artist, durationMs: durationMs)
        guard let best = SongMatcher.bestMatch(for: query, in: candidates),
              let synced = tracks.first(where: { $0.id == best.id })?.syncedLyrics else { return nil }
        let lyrics = LyricsParser.parse(lrc: synced, yrc: nil)
        return lyrics.isEmpty ? nil : lyrics
    }

    /// 按歌名(+ 歌手)搜索;歌手为空时只按歌名搜。
    func search(title: String, artist: String) async throws -> [Track] {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [.init(name: "track_name", value: title)]
        if !artist.isEmpty { comps.queryItems?.append(.init(name: "artist_name", value: artist)) }
        let data = try await LyricsHTTP.get(comps.url!, headers: Self.headers, session: session)
        do {
            return try JSONDecoder().decode([Track].self, from: data)
        } catch { throw NeteaseAPIError.decoding }
    }

    /// 搜索结果条目(仅取需要的字段)。duration 单位为秒。
    struct Track: Decodable {
        let id: Int64
        let trackName: String
        let artistName: String
        let duration: Double?
        let instrumental: Bool
        let syncedLyrics: String?
    }
}
