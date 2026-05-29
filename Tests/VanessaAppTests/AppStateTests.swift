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

/// 假仓储:按需返回 matched / lowConfidence。
private struct FakeRepo: LyricsRepository {
    let result: LyricsLookupResult
    func lookup(title: String, artist: String, durationMs: Int) async throws -> LyricsLookupResult { result }
}

@MainActor
final class AppStateTests: XCTestCase {
    private func playing(_ title: String, _ artist: String, lrcText: String = "行") -> NowPlayingState {
        NowPlayingState(title: title, artist: artist, album: "", artworkData: nil,
                        duration: 200, elapsed: 1, sampledAt: Date(timeIntervalSince1970: 1000),
                        rate: 1, isPlaying: true, sourceBundleID: neteaseBundleIDDefault)
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
}
