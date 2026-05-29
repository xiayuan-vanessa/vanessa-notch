import XCTest
@testable import VanessaCore

final class LyricSyncEngineTests: XCTestCase {
    private func sample() -> Lyrics {
        Lyrics(lines: [
            LyricLine(startMs: 1000, endMs: 3000, text: "我爱你",
                      words: [Word(startMs: 1000, endMs: 1500, text: "我"),
                              Word(startMs: 1500, endMs: 2000, text: "爱"),
                              Word(startMs: 2000, endMs: 3000, text: "你")]),
            LyricLine(startMs: 4000, endMs: 6000, text: "再见", words: []),
        ])
    }

    func test_beforeFirstLine_noHighlight() {
        let p = LyricSyncEngine.locate(positionMs: 500, in: sample())
        XCTAssertNil(p.lineIndex)
    }

    func test_insideFirstLine_picksActiveWordAndProgress() {
        let p = LyricSyncEngine.locate(positionMs: 1750, in: sample())
        XCTAssertEqual(p.lineIndex, 0)
        XCTAssertEqual(p.activeWordIndex, 1)
        XCTAssertEqual(p.wordProgress, 0.5, accuracy: 0.001)
    }

    func test_gapBetweenLines_holdsPreviousLineCompleted() {
        let p = LyricSyncEngine.locate(positionMs: 3500, in: sample())
        XCTAssertEqual(p.lineIndex, 0)
        XCTAssertEqual(p.activeWordIndex, 2)
        XCTAssertEqual(p.wordProgress, 1.0, accuracy: 0.001)
        XCTAssertEqual(p.lineProgress, 1.0, accuracy: 0.001)
    }

    func test_lineWithoutWords_usesLineProgress() {
        let p = LyricSyncEngine.locate(positionMs: 5000, in: sample())
        XCTAssertEqual(p.lineIndex, 1)
        XCTAssertNil(p.activeWordIndex)
        XCTAssertEqual(p.lineProgress, 0.5, accuracy: 0.001)
    }

    func test_pastLastLine_clampsToCompleted() {
        let p = LyricSyncEngine.locate(positionMs: 99999, in: sample())
        XCTAssertEqual(p.lineIndex, 1)
        XCTAssertEqual(p.lineProgress, 1.0, accuracy: 0.001)
    }

    func test_emptyLyrics_noHighlight() {
        let p = LyricSyncEngine.locate(positionMs: 1000, in: Lyrics(lines: []))
        XCTAssertEqual(p, .none)
    }
}
