import XCTest
import Foundation
@testable import VanessaCore

final class ModelsTests: XCTestCase {
    func test_nowPlayingState_equatable() {
        let now = Date(timeIntervalSince1970: 1000)
        let a = NowPlayingState(title: "歌", artist: "人", album: "碟", artworkData: nil,
                                duration: 200, elapsed: 10, sampledAt: now, rate: 1,
                                isPlaying: true, sourceBundleID: "com.netease.163music")
        let b = a
        XCTAssertEqual(a, b)
    }

    func test_lyricLine_emptyWords_meansNoKaraoke() {
        let line = LyricLine(startMs: 0, endMs: 1000, text: "hi", words: [])
        XCTAssertTrue(line.words.isEmpty)
    }
}
