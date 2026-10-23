import XCTest
import VanessaCore
import VanessaNetease
@testable import VanessaApp

/// 可手动投喂状态的假 provider。
private final class FakeProvider: NowPlayingProvider, @unchecked Sendable {
    let states: AsyncStream<NowPlayingState?>
    private let cont: AsyncStream<NowPlayingState?>.Continuation
    var started = false
    init() { var c: AsyncStream<NowPlayingState?>.Continuation!; states = AsyncStream { c = $0 }; cont = c }
    func start() { started = true }
    func stop() { cont.finish() }
    func emit(_ s: NowPlayingState?) { cont.yield(s) }
}

/// 假仓储:按需返回 matched / lowConfidence;按 ID 取歌词时从 byID 查找。
private struct FakeRepo: LyricsRepository {
    let result: LyricsLookupResult
    var byID: [Int64: Lyrics] = [:]
    func lookup(title: String, artist: String, durationMs: Int) async throws -> LyricsLookupResult { result }
    func search(keywords: String) async throws -> [SongCandidate] { [] }
    func lyrics(forSongID id: Int64) async throws -> Lyrics {
        guard let lyrics = byID[id] else { throw URLError(.fileDoesNotExist) }
        return lyrics
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    private func playing(_ title: String, _ artist: String, lrcText: String = "行") -> NowPlayingState {
        NowPlayingState(title: title, artist: artist, album: "", artworkData: nil,
                        duration: 200, elapsed: 1, sampledAt: Date(timeIntervalSince1970: 1000),
                        rate: 1, isPlaying: true, sourceBundleID: "com.netease.163music")
    }

    func test_initialState_isIdle() {
        let state = AppState(provider: FakeProvider(),
                             repository: FakeRepo(result: .lowConfidence))
        XCTAssertEqual(state.ui, .idle)
    }

    func test_nilEmission_staysIdle() async {
        let p = FakeProvider()
        let state = AppState(provider: p, repository: FakeRepo(result: .lowConfidence))
        state.start()
        p.emit(nil)
        await state.drainForTesting()
        XCTAssertEqual(state.ui, .idle)
    }

    func test_matchedSong_entersPlayingWithLyrics() async {
        let p = FakeProvider()
        let lyrics = Lyrics(lines: [LyricLine(startMs: 0, endMs: 5000, text: "我爱你", words: [])])
        let state = AppState(provider: p, repository: FakeRepo(result: .matched(songID: 1, lyrics: lyrics)))
        state.start()
        p.emit(playing("晴天", "周杰伦"))
        await state.drainForTesting()
        guard case .playing(let d) = state.ui else { return XCTFail("应进入 playing") }
        XCTAssertEqual(d.title, "晴天")
        XCTAssertEqual(d.lineText, "我爱你")
    }

    func test_lowConfidence_showsTitleArtistFallback() async {
        let p = FakeProvider()
        let state = AppState(provider: p, repository: FakeRepo(result: .lowConfidence))
        state.start()
        p.emit(playing("某歌", "某人"))
        await state.drainForTesting()
        guard case .playing(let d) = state.ui else { return XCTFail("应进入 playing") }
        XCTAssertEqual(d.lineText, "某歌 - 某人")
    }

    func test_matchedButEmptyLyrics_showsInstrumentalPlaceholder() async {
        let p = FakeProvider()
        let state = AppState(provider: p, repository: FakeRepo(result: .matched(songID: 1, lyrics: Lyrics(lines: []))))
        state.start()
        p.emit(playing("纯音乐曲", "演奏者"))
        await state.drainForTesting()
        guard case .playing(let d) = state.ui else { return XCTFail("应进入 playing") }
        XCTAssertEqual(d.lineText, "♪ 纯音乐")
    }

    // MARK: - 手动校正

    private func isolatedPreferences() -> SongPreferences {
        SongPreferences(defaults: UserDefaults(suiteName: "AppStateTests-\(UUID().uuidString)")!)
    }

    private func line(_ text: String) -> Lyrics {
        Lyrics(lines: [LyricLine(startMs: 0, endMs: 300_000, text: text, words: [])])
    }

    func test_manualSongID_takesPrecedenceOverLookup() async {
        let p = FakeProvider()
        let prefs = isolatedPreferences()
        let song = playing("晴天", "周杰伦")
        prefs.setSongID(42, for: song.songIdentity)
        let repo = FakeRepo(result: .matched(songID: 1, lyrics: line("自动匹配")), byID: [42: line("手动指定")])
        let state = AppState(provider: p, repository: repo, preferences: prefs)
        state.start()
        p.emit(song)
        await state.drainForTesting()
        guard case .playing(let d) = state.ui else { return XCTFail("应进入 playing") }
        XCTAssertEqual(d.lineText, "手动指定")
    }

    func test_applyManualMatch_replacesLyricsAndRemembersChoice() async throws {
        let p = FakeProvider()
        let prefs = isolatedPreferences()
        let song = playing("某歌", "某人")
        let state = AppState(provider: p, repository: FakeRepo(result: .lowConfidence, byID: [7: line("正确歌词")]),
                             preferences: prefs)
        state.start()
        p.emit(song)
        await state.drainForTesting()
        try await state.applyManualMatch(songID: 7, for: song.songIdentity)
        guard case .playing(let d) = state.ui else { return XCTFail("应进入 playing") }
        XCTAssertEqual(d.lineText, "正确歌词")
        XCTAssertEqual(prefs.songID(for: song.songIdentity), 7)
    }

    func test_applyManualMatch_fetchFails_doesNotRememberChoice() async {
        let prefs = isolatedPreferences()
        let song = playing("某歌", "某人")
        let state = AppState(provider: FakeProvider(), repository: FakeRepo(result: .lowConfidence),
                             preferences: prefs)
        do {
            try await state.applyManualMatch(songID: 99, for: song.songIdentity)
            XCTFail("应抛错")
        } catch {}
        XCTAssertNil(prefs.songID(for: song.songIdentity))
    }

    func test_songOffset_persistsAndZeroRemoves() {
        let prefs = isolatedPreferences()
        prefs.setOffsetMs(300, for: "a")
        XCTAssertEqual(prefs.offsetMs(for: "a"), 300)
        prefs.setOffsetMs(0, for: "a")
        XCTAssertEqual(prefs.offsetMs(for: "a"), 0)
    }
}
