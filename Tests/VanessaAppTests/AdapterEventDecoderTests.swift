import XCTest
import VanessaCore
@testable import VanessaApp

final class AdapterEventDecoderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 5000)
    private let netease = "com.netease.163music"

    /// adapter 真实输出为信封格式:{"type":"data","diff":false,"payload":{...}}。
    func test_envelopeFormat_unwrapsPayload() throws {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.netease.163music","playing":false,"title":"风起天阑","artist":"河图","duration":328.0,"elapsedTime":112.0,"playbackRate":0}}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now, neteaseBundleID: netease))
        XCTAssertEqual(s.title, "风起天阑")
        XCTAssertEqual(s.artist, "河图")
        XCTAssertEqual(s.elapsed, 112, accuracy: 0.001)
        XCTAssertFalse(s.isPlaying)
    }

    /// 采样时刻应取自 payload 的 timestamp(而非传入的 now),用于正确推算播放中途接入的进度。
    func test_timestampUsedAsSampledAt() throws {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.netease.163music","playing":true,"title":"a","artist":"b","duration":300,"elapsedTime":100,"timestamp":"2026-05-29T02:18:13Z"}}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now, neteaseBundleID: netease))
        XCTAssertNotEqual(s.sampledAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        let expected = ISO8601DateFormatter().date(from: "2026-05-29T02:18:13Z")!
        XCTAssertEqual(s.sampledAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    /// 非 data 类型信封应忽略。
    func test_nonDataEnvelope_returnsNil() {
        XCTAssertNil(AdapterEventDecoder.decode(line: #"{"type":"ping"}"#, sampledAt: now, neteaseBundleID: netease))
    }

    /// 空 payload 信封应返回 nil(无 bundleIdentifier)。
    func test_emptyPayloadEnvelope_returnsNil() {
        XCTAssertNil(AdapterEventDecoder.decode(line: #"{"type":"data","diff":false,"payload":{}}"#, sampledAt: now, neteaseBundleID: netease))
    }

    func test_neteaseSource_decodesState() throws {
        let line = """
        {"bundleIdentifier":"com.netease.163music","playing":true,"title":"晴天","artist":"周杰伦",
         "album":"叶惠美","duration":269.0,"elapsedTime":42.0,"playbackRate":1.0}
        """
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now, neteaseBundleID: netease))
        XCTAssertEqual(s.title, "晴天")
        XCTAssertEqual(s.artist, "周杰伦")
        XCTAssertEqual(s.duration, 269, accuracy: 0.001)
        XCTAssertEqual(s.elapsed, 42, accuracy: 0.001)
        XCTAssertTrue(s.isPlaying)
        XCTAssertEqual(s.rate, 1)
        XCTAssertEqual(s.sampledAt, now)
        XCTAssertEqual(s.sourceBundleID, netease)
    }

    func test_nonNeteaseSource_returnsNil() throws {
        let line = #"{"bundleIdentifier":"com.apple.Music","playing":true,"title":"x","artist":"y","duration":100,"elapsedTime":1}"#
        XCTAssertNil(AdapterEventDecoder.decode(line: line, sampledAt: now, neteaseBundleID: netease))
    }

    func test_parentBundleIdAlsoMatches() throws {
        let line = #"{"bundleIdentifier":"com.netease.helper","parentApplicationBundleIdentifier":"com.netease.163music","playing":true,"title":"a","artist":"b","duration":10,"elapsedTime":1}"#
        XCTAssertNotNil(AdapterEventDecoder.decode(line: line, sampledAt: now, neteaseBundleID: netease))
    }

    func test_missingOptionalFields_useDefaults() throws {
        let line = #"{"bundleIdentifier":"com.netease.163music","title":"纯音乐","duration":120,"elapsedTime":0}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now, neteaseBundleID: netease))
        XCTAssertEqual(s.artist, "")
        XCTAssertFalse(s.isPlaying)
        XCTAssertEqual(s.rate, 1)
    }

    func test_garbageLine_returnsNil() {
        XCTAssertNil(AdapterEventDecoder.decode(line: "not json", sampledAt: now, neteaseBundleID: netease))
        XCTAssertNil(AdapterEventDecoder.decode(line: "", sampledAt: now, neteaseBundleID: netease))
    }
}
