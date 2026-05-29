import XCTest
import VanessaCore
@testable import VanessaNetease

final class NeteaseAPIClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func test_search_decodesCandidates() async throws {
        let json = """
        {"result":{"songs":[
          {"id":111,"name":"晴天","duration":269000,"artists":[{"name":"周杰伦"}]},
          {"id":222,"name":"雨天","duration":200000,"artists":[{"name":"某人"},{"name":"另一人"}]}
        ]},"code":200}
        """
        StubURLProtocol.stubs = ["search/get": .init(data: Data(json.utf8), statusCode: 200, error: nil)]
        let client = NeteaseAPIClient(session: StubURLProtocol.session())
        let cands = try await client.search(title: "晴天", artist: "周杰伦")
        XCTAssertEqual(cands.count, 2)
        XCTAssertEqual(cands[0], SongCandidate(id: 111, title: "晴天", artists: ["周杰伦"], durationMs: 269000))
        XCTAssertEqual(cands[1].artists, ["某人", "另一人"])
    }

    func test_fetchLyrics_returnsLrcAndYrc() async throws {
        let json = """
        {"lrc":{"lyric":"[00:01.00]行"},"yrc":{"lyric":"[1000,500](1000,500,0)字"},"code":200}
        """
        StubURLProtocol.stubs = ["song/lyric": .init(data: Data(json.utf8), statusCode: 200, error: nil)]
        let client = NeteaseAPIClient(session: StubURLProtocol.session())
        let raw = try await client.fetchLyrics(songID: 111)
        XCTAssertEqual(raw.lrc, "[00:01.00]行")
        XCTAssertEqual(raw.yrc, "[1000,500](1000,500,0)字")
    }

    func test_fetchLyrics_missingYrc_isNil() async throws {
        let json = #"{"lrc":{"lyric":"[00:01.00]行"},"code":200}"#
        StubURLProtocol.stubs = ["song/lyric": .init(data: Data(json.utf8), statusCode: 200, error: nil)]
        let client = NeteaseAPIClient(session: StubURLProtocol.session())
        let raw = try await client.fetchLyrics(songID: 111)
        XCTAssertNil(raw.yrc)
    }

    func test_networkError_throws() async {
        StubURLProtocol.stubs = ["search/get": .init(data: Data(), statusCode: 0, error: URLError(.notConnectedToInternet))]
        let client = NeteaseAPIClient(session: StubURLProtocol.session())
        do { _ = try await client.search(title: "x", artist: "y"); XCTFail("应抛错") }
        catch {}
    }

    func test_httpError_throwsBadStatus() async {
        StubURLProtocol.stubs = ["search/get": .init(data: Data("{}".utf8), statusCode: 503, error: nil)]
        let client = NeteaseAPIClient(session: StubURLProtocol.session())
        do { _ = try await client.search(title: "x", artist: "y"); XCTFail("应抛错") }
        catch NeteaseAPIError.badStatus(let code) { XCTAssertEqual(code, 503) }
        catch { XCTFail("应为 badStatus,实际:\(error)") }
    }
}
