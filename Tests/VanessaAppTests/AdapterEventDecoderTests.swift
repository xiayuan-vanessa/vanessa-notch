import XCTest
import VanessaCore
@testable import VanessaApp

final class AdapterEventDecoderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 5000)

    /// adapter 真实输出为信封格式:{"type":"data","diff":false,"payload":{...}}。
    func test_envelopeFormat_unwrapsPayload() throws {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.netease.163music","playing":false,"title":"风起天阑","artist":"河图","duration":328.0,"elapsedTime":112.0,"playbackRate":0}}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now))
        XCTAssertEqual(s.title, "风起天阑")
        XCTAssertEqual(s.artist, "河图")
        XCTAssertEqual(s.elapsed, 112, accuracy: 0.001)
        XCTAssertFalse(s.isPlaying)
    }

    /// 采样时刻始终用传入的 sampledAt(Date())。
    func test_timestampIgnored_usesSampledAt() throws {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.netease.163music","playing":true,"title":"a","artist":"b","duration":300,"elapsedTime":100,"timestamp":"2026-05-29T02:18:13Z"}}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now))
        XCTAssertEqual(s.sampledAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    /// 非 data 类型信封应忽略。
    func test_nonDataEnvelope_returnsNil() {
        XCTAssertNil(AdapterEventDecoder.decode(line: #"{"type":"ping"}"#, sampledAt: now))
    }

    /// 空 payload 信封应返回 nil(无 bundleIdentifier)。
    func test_emptyPayloadEnvelope_returnsNil() {
        XCTAssertNil(AdapterEventDecoder.decode(line: #"{"type":"data","diff":false,"payload":{}}"#, sampledAt: now))
    }

    /// 网易云来源正常解码。
    func test_neteaseSource_decodesState() throws {
        let line = """
        {"bundleIdentifier":"com.netease.163music","playing":true,"title":"晴天","artist":"周杰伦",
         "album":"叶惠美","duration":269.0,"elapsedTime":42.0,"playbackRate":1.0}
        """
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now))
        XCTAssertEqual(s.title, "晴天")
        XCTAssertEqual(s.sourceBundleID, "com.netease.163music")
    }

    /// Apple Music 来源也能解码（多播放源支持）。
    func test_appleMusicSource_decodesState() throws {
        let line = #"{"bundleIdentifier":"com.apple.Music","playing":true,"title":"x","artist":"y","duration":100,"elapsedTime":1}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now))
        XCTAssertEqual(s.sourceBundleID, "com.apple.Music")
        XCTAssertEqual(s.title, "x")
    }

    /// Spotify 来源也能解码。
    func test_spotifySource_decodesState() throws {
        let line = #"{"bundleIdentifier":"com.spotify.client","playing":true,"title":"Shape of You","artist":"Ed Sheeran","duration":234,"elapsedTime":10}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now))
        XCTAssertEqual(s.sourceBundleID, "com.spotify.client")
    }

    /// 缺少可选字段时使用默认值。
    func test_missingOptionalFields_useDefaults() throws {
        let line = #"{"bundleIdentifier":"com.netease.163music","title":"纯音乐","duration":120,"elapsedTime":0}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now))
        XCTAssertEqual(s.artist, "")
        XCTAssertFalse(s.isPlaying)
        XCTAssertEqual(s.rate, 1)
    }

    func test_garbageLine_returnsNil() {
        XCTAssertNil(AdapterEventDecoder.decode(line: "not json", sampledAt: now))
        XCTAssertNil(AdapterEventDecoder.decode(line: "", sampledAt: now))
    }
}
