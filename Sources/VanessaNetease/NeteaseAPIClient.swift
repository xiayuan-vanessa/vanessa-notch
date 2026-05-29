import Foundation
import VanessaCore

/// 网络层错误。
public enum NeteaseAPIError: Error, Equatable {
    case badStatus(Int)
    case decoding
}

/// 歌词原始文本(未解析)。
public struct RawLyrics: Equatable, Sendable {
    public let lrc: String?
    public let yrc: String?
}

/// 数据源抽象:便于仓储注入假实现做单测。
public protocol NeteaseDataSource: Sendable {
    func search(title: String, artist: String) async throws -> [SongCandidate]
    func fetchLyrics(songID: Int64) async throws -> RawLyrics
}

/// 封装网易云搜索 / 歌词两个非官方接口。所有网络经注入的 URLSession,便于打桩。
public struct NeteaseAPIClient: NeteaseDataSource, Sendable {
    private let session: URLSession
    private let baseURL: String

    public init(session: URLSession = .shared, baseURL: String = "https://music.163.com/api") {
        self.session = session
        self.baseURL = baseURL
    }

    /// 搜索:用「歌名 歌手」作为关键词,返回候选列表。
    public func search(title: String, artist: String) async throws -> [SongCandidate] {
        let keywords = "\(title) \(artist)".trimmingCharacters(in: .whitespaces)
        let q = keywords.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keywords
        let url = URL(string: "\(baseURL)/search/get?s=\(q)&type=1&limit=10")!
        let data = try await get(url)
        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return decoded.result.songs.map {
                SongCandidate(id: $0.id, title: $0.name,
                              artists: $0.artists.map { $0.name }, durationMs: $0.duration)
            }
        } catch { throw NeteaseAPIError.decoding }
    }

    /// 拉取指定歌曲 ID 的 LRC + YRC 原始文本。
    public func fetchLyrics(songID: Int64) async throws -> RawLyrics {
        let url = URL(string: "\(baseURL)/song/lyric?id=\(songID)&lv=1&kv=1&yv=1")!
        let data = try await get(url)
        do {
            let decoded = try JSONDecoder().decode(LyricResponse.self, from: data)
            let lrc = decoded.lrc?.lyric.flatMap { $0.isEmpty ? nil : $0 }
            let yrc = decoded.yrc?.lyric.flatMap { $0.isEmpty ? nil : $0 }
            return RawLyrics(lrc: lrc, yrc: yrc)
        } catch { throw NeteaseAPIError.decoding }
    }

    /// GET 并校验 HTTP 状态。
    private func get(_ url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NeteaseAPIError.badStatus(http.statusCode)
        }
        return data
    }

    // MARK: - 解码模型(仅取需要的字段)
    private struct SearchResponse: Decodable {
        struct Result: Decodable { let songs: [Song] }
        struct Song: Decodable { let id: Int64; let name: String; let duration: Int; let artists: [Artist] }
        struct Artist: Decodable { let name: String }
        let result: Result
    }
    private struct LyricResponse: Decodable {
        struct Lyric: Decodable { let lyric: String? }
        let lrc: Lyric?
        let yrc: Lyric?
    }
}
