import XCTest
import VanessaCore
@testable import VanessaNetease

/// 假主源:返回预设结果或抛错,并记录调用次数。
private final class FakePrimary: LyricsRepository, @unchecked Sendable {
    let result: Result<LyricsLookupResult, Error>
    var calls = 0
    init(_ result: Result<LyricsLookupResult, Error>) { self.result = result }
    func lookup(title: String, artist: String, durationMs: Int) async throws -> LyricsLookupResult {
        calls += 1
        return try result.get()
    }
    func search(keywords: String) async throws -> [SongCandidate] { [] }
    func lyrics(forSongID id: Int64) async throws -> Lyrics { Lyrics(lines: []) }
}

/// 假兜底源:返回预设歌词或抛错,并记录调用次数。
private final class FakeSource: FallbackLyricsSource, @unchecked Sendable {
    let name: String
    let result: Result<Lyrics?, Error>
    var calls = 0
    init(_ name: String, _ result: Result<Lyrics?, Error>) { self.name = name; self.result = result }
    func lyrics(title: String, artist: String, durationMs: Int) async throws -> Lyrics? {
        calls += 1
        return try result.get()
    }
}

final class FallbackLyricsRepositoryTests: XCTestCase {
    private func tempCache() -> LyricsCache {
        LyricsCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("FallbackTests-\(UUID().uuidString)"))
    }

    private func lyrics(_ text: String) -> Lyrics {
        Lyrics(lines: [LyricLine(startMs: 0, endMs: 1000, text: text, words: [])])
    }

    private func matchedText(_ r: LyricsLookupResult) -> String? {
        if case .matched(_, let l) = r { return l.lines.first?.text }
        return nil
    }

    func test_primaryHasLyrics_skipsFallbackSources() async throws {
        let primary = FakePrimary(.success(.matched(songID: 1, lyrics: lyrics("网易云"))))
        let qq = FakeSource("qq", .success(lyrics("QQ")))
        let repo = FallbackLyricsRepository(primary: primary, sources: [qq], cache: tempCache())
        let r = try await repo.lookup(title: "a", artist: "b", durationMs: 1000)
        XCTAssertEqual(matchedText(r), "网易云")
        XCTAssertEqual(qq.calls, 0)
    }

    func test_primaryLowConfidence_usesFirstSourceWithLyrics() async throws {
        let empty = FakeSource("qq", .success(nil))
        let lrclib = FakeSource("lrclib", .success(lyrics("LRCLIB")))
        let repo = FallbackLyricsRepository(primary: FakePrimary(.success(.lowConfidence)),
                                            sources: [empty, lrclib], cache: tempCache())
        let r = try await repo.lookup(title: "a", artist: "b", durationMs: 1000)
        XCTAssertEqual(matchedText(r), "LRCLIB")
        XCTAssertEqual(empty.calls, 1)
    }

    func test_sourceError_continuesToNextSource() async throws {
        let broken = FakeSource("qq", .failure(URLError(.timedOut)))
        let lrclib = FakeSource("lrclib", .success(lyrics("LRCLIB")))
        let repo = FallbackLyricsRepository(primary: FakePrimary(.success(.lowConfidence)),
                                            sources: [broken, lrclib], cache: tempCache())
        let r = try await repo.lookup(title: "a", artist: "b", durationMs: 1000)
        XCTAssertEqual(matchedText(r), "LRCLIB")
    }

    func test_primaryErrorAndNoFallback_rethrowsPrimaryError() async {
        let repo = FallbackLyricsRepository(primary: FakePrimary(.failure(URLError(.notConnectedToInternet))),
                                            sources: [FakeSource("qq", .success(nil))], cache: tempCache())
        do {
            _ = try await repo.lookup(title: "a", artist: "b", durationMs: 1000)
            XCTFail("应抛出主源错误")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func test_primaryEmptyLyricsAndNoFallback_keepsInstrumentalResult() async throws {
        let repo = FallbackLyricsRepository(primary: FakePrimary(.success(.matched(songID: 9, lyrics: Lyrics(lines: [])))),
                                            sources: [FakeSource("qq", .success(nil))], cache: tempCache())
        let r = try await repo.lookup(title: "a", artist: "b", durationMs: 1000)
        XCTAssertEqual(r, .matched(songID: 9, lyrics: Lyrics(lines: [])))
    }

    func test_fallbackResultIsCached_secondLookupSkipsNetwork() async throws {
        let cache = tempCache()
        let primary = FakePrimary(.success(.lowConfidence))
        let qq = FakeSource("qq", .success(lyrics("QQ")))
        let repo = FallbackLyricsRepository(primary: primary, sources: [qq], cache: cache)
        _ = try await repo.lookup(title: "a", artist: "b", durationMs: 1000)
        let r = try await repo.lookup(title: "a", artist: "b", durationMs: 1000)
        XCTAssertEqual(matchedText(r), "QQ")
        XCTAssertEqual(primary.calls, 1, "命中兜底缓存时不应再查主源")
        XCTAssertEqual(qq.calls, 1, "命中兜底缓存时不应再查兜底源")
    }
}
