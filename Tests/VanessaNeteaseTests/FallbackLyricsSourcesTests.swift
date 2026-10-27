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
