import XCTest
import VanessaCore
@testable import VanessaNetease

/// QQ 音乐 / LRCLIB 兜底源:用 StubURLProtocol 模拟接口返回,验证选歌与解析。
final class FallbackLyricsSourcesTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func stub(_ key: String, _ json: String) -> (String, StubURLProtocol.Stub) {
        (key, .init(data: Data(json.utf8), statusCode: 200, error: nil))
    }

    func test_qq_picksMatchingSongAndAttachesTranslation() async throws {
        let search = """
        {"data":{"song":{"list":[
          {"songid":1,"songmid":"LIVE","songname":"晴天 (Live)","interval":330,"singer":[{"name":"周杰伦"}]},
          {"songid":2,"songmid":"STUDIO","songname":"晴天","interval":269,"singer":[{"name":"周杰伦"}]}
        ]}}}
        """
        let lyric = #"{"retcode":0,"lyric":"[00:01.00]故事的小黄花\n[00:03.00]从出生那年就飘着","trans":"[00:01.00]Little yellow flower"}"#
        StubURLProtocol.stubs = Dictionary(uniqueKeysWithValues: [
            stub("client_search_cp", search), stub("songmid=STUDIO", lyric)])
        let source = QQMusicLyricsSource(session: StubURLProtocol.session())
        let lyrics = try await source.lyrics(title: "晴天", artist: "周杰伦", durationMs: 269_000)
        XCTAssertEqual(lyrics?.lines.first?.text, "故事的小黄花")
        XCTAssertEqual(lyrics?.lines.first?.translation, "Little yellow flower")
        XCTAssertEqual(lyrics?.lines.count, 2)
    }

    func test_qq_noConfidentMatch_returnsNil() async throws {
        let search = """
        {"data":{"song":{"list":[
          {"songid":1,"songmid":"X","songname":"完全不同的歌","interval":100,"singer":[{"name":"别人"}]}
        ]}}}
        """
        StubURLProtocol.stubs = Dictionary(uniqueKeysWithValues: [stub("client_search_cp", search)])
        let source = QQMusicLyricsSource(session: StubURLProtocol.session())
        let lyrics = try await source.lyrics(title: "晴天", artist: "周杰伦", durationMs: 269_000)
        XCTAssertNil(lyrics)
    }

    func test_lrclib_skipsInstrumentalAndUnsyncedCandidates() async throws {
        let json = """
        [
          {"id":1,"trackName":"Blinding Lights","artistName":"The Weeknd","duration":200,"instrumental":true,"syncedLyrics":null},
          {"id":2,"trackName":"Blinding Lights","artistName":"The Weeknd","duration":200,"instrumental":false,"syncedLyrics":null},
          {"id":3,"trackName":"Blinding Lights","artistName":"The Weeknd","duration":201,"instrumental":false,
           "syncedLyrics":"[00:13.42] Yeah\\n[00:26.95] I've been tryna call"}
        ]
        """
        StubURLProtocol.stubs = Dictionary(uniqueKeysWithValues: [stub("api/search", json)])
        let source = LRCLIBLyricsSource(session: StubURLProtocol.session())
        let lyrics = try await source.lyrics(title: "Blinding Lights", artist: "The Weeknd", durationMs: 200_000)
        XCTAssertEqual(lyrics?.lines.map(\.text), ["Yeah", "I've been tryna call"])
        XCTAssertEqual(lyrics?.lines.first?.startMs, 13_420)
    }

    /// 真实复现:播放「江南|林俊杰|254s」,QQ 只有时长相近的演唱会现场版(252s)。
    /// 现场版是另一段录音,时间轴整体错位,不应被选中;宁可返回 nil 走「歌名 - 歌手」降级。
    func test_qq_rejectsLiveVersionWhenPlayingTitleHasNoVersionMarker() async throws {
        let search = """
        {"data":{"song":{"list":[
          {"songid":1,"songmid":"STUDIO","songname":"江南","interval":267,"singer":[{"name":"林俊杰"}]},
          {"songid":2,"songmid":"WUHAN","songname":"江南 (2023 JJ20世界巡回演唱会武汉站)","interval":252,"singer":[{"name":"林俊杰"},{"name":"李健"}]},
          {"songid":3,"songmid":"YUE","songname":"江南 (粤语)","interval":255,"singer":[{"name":"林俊杰"}]}
        ]}}}
        """
        StubURLProtocol.stubs = Dictionary(uniqueKeysWithValues: [
            stub("client_search_cp", search), stub("songmid=", #"{"lyric":"[00:25.21]风到这里就是黏"}"#)])
        let source = QQMusicLyricsSource(session: StubURLProtocol.session())
        let lyrics = try await source.lyrics(title: "江南", artist: "林俊杰", durationMs: 254_000)
        XCTAssertNil(lyrics)
    }

    /// 播放的本身就是现场版(标题带 Live)时,现场版候选可以匹配。
    func test_qq_allowsLiveVersionWhenPlayingTitleIsLive() async throws {
        let search = """
        {"data":{"song":{"list":[
          {"songid":1,"songmid":"LIVE","songname":"江南 (Live)","interval":268,"singer":[{"name":"林俊杰"}]}
        ]}}}
        """
        StubURLProtocol.stubs = Dictionary(uniqueKeysWithValues: [
            stub("client_search_cp", search), stub("songmid=LIVE", #"{"lyric":"[00:25.21]风到这里就是黏"}"#)])
        let source = QQMusicLyricsSource(session: StubURLProtocol.session())
        let lyrics = try await source.lyrics(title: "江南 (Live)", artist: "林俊杰", durationMs: 268_000)
        XCTAssertEqual(lyrics?.lines.first?.text, "风到这里就是黏")
    }

    func test_lrclib_rejectsRemixWhenPlayingOriginal() async throws {
        let json = """
        [{"id":1,"trackName":"Blinding Lights (Remix)","artistName":"The Weeknd","duration":200,"instrumental":false,
          "syncedLyrics":"[00:01.00] Yeah"}]
        """
        StubURLProtocol.stubs = Dictionary(uniqueKeysWithValues: [stub("api/search", json)])
        let source = LRCLIBLyricsSource(session: StubURLProtocol.session())
        let lyrics = try await source.lyrics(title: "Blinding Lights", artist: "The Weeknd", durationMs: 200_000)
        XCTAssertNil(lyrics)
    }

    func test_lrclib_badStatus_throws() async {
        StubURLProtocol.stubs = ["api/search": .init(data: Data(), statusCode: 500, error: nil)]
        let source = LRCLIBLyricsSource(session: StubURLProtocol.session())
        do {
            _ = try await source.lyrics(title: "a", artist: "b", durationMs: 1000)
            XCTFail("应抛错")
        } catch {
            XCTAssertEqual(error as? NeteaseAPIError, .badStatus(500))
        }
    }
}
