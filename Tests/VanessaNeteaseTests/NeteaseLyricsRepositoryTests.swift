import XCTest
import VanessaCore
@testable import VanessaNetease

/// 假数据源:记录调用次数,返回预置数据。
private final class FakeSource: NeteaseDataSource, @unchecked Sendable {
    var candidates: [SongCandidate] = []
    var raw: [Int64: RawLyrics] = [:]
    private(set) var searchCalls = 0
    private(set) var lyricCalls = 0
    func search(title: String, artist: String) async throws -> [SongCandidate] { searchCalls += 1; return candidates }
    func fetchLyrics(songID: Int64) async throws -> RawLyrics { lyricCalls += 1; return raw[songID] ?? RawLyrics(lrc: nil, yrc: nil) }
}

final class NeteaseLyricsRepositoryTests: XCTestCase {
    private func tmpCache() -> LyricsCache {
        LyricsCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("repo-test-\(UUID().uuidString)"))
    }

    func test_matchedSong_returnsParsedLyricsAndCaches() async throws {
        let src = FakeSource()
        src.candidates = [SongCandidate(id: 111, title: "晴天", artists: ["周杰伦"], durationMs: 269000)]
        src.raw[111] = RawLyrics(lrc: "[00:01.00]行", yrc: nil)
        let cache = tmpCache()
        let repo = NeteaseLyricsRepository(source: src, cache: cache)
        let result = try await repo.lookup(title: "晴天", artist: "周杰伦", durationMs: 269000)
        guard case .matched(let id, let lyrics) = result else { return XCTFail("应为 matched") }
        XCTAssertEqual(id, 111)
        XCTAssertEqual(lyrics.lines.first?.text, "行")
        XCTAssertEqual(cache.lyrics(forSongID: 111)?.lines.first?.text, "行")
    }

    func test_cacheHit_skipsNetwork() async throws {
        let src = FakeSource()
        src.candidates = [SongCandidate(id: 111, title: "晴天", artists: ["周杰伦"], durationMs: 269000)]
        src.raw[111] = RawLyrics(lrc: "[00:01.00]行", yrc: nil)
        let cache = tmpCache()
        let repo = NeteaseLyricsRepository(source: src, cache: cache)
        _ = try await repo.lookup(title: "晴天", artist: "周杰伦", durationMs: 269000)
        let before = src.lyricCalls
        _ = try await repo.lookup(title: "晴天", artist: "周杰伦", durationMs: 269000)
        XCTAssertEqual(src.lyricCalls, before)
    }

    func test_lowConfidence_returnsLowConfidence() async throws {
        let src = FakeSource()
        src.candidates = [SongCandidate(id: 999, title: "毫不相干XYZ", artists: ["别人"], durationMs: 999000)]
        let repo = NeteaseLyricsRepository(source: src, cache: tmpCache())
        let result = try await repo.lookup(title: "原曲ABC", artist: "原唱", durationMs: 100000)
        XCTAssertEqual(result, .lowConfidence)
        XCTAssertEqual(src.lyricCalls, 0)
    }

    func test_emptyCandidates_lowConfidence() async throws {
        let repo = NeteaseLyricsRepository(source: FakeSource(), cache: tmpCache())
        let result = try await repo.lookup(title: "x", artist: "y", durationMs: 1000)
        XCTAssertEqual(result, .lowConfidence)
    }
}
