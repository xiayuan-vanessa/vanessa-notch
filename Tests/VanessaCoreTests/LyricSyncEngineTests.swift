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

    /// 字与字之间有停顿(如「可以 很长」的空格处):应保持上一个字已唱完,
    /// 而不是退回按时间计算的 lineProgress(那会让高亮往回跳)。
    func test_gapBetweenWords_holdsPreviousWordCompleted() {
        let lyrics = Lyrics(lines: [
            LyricLine(startMs: 1000, endMs: 4000, text: "可以很长",
                      words: [Word(startMs: 1000, endMs: 1500, text: "可"),
                              Word(startMs: 1500, endMs: 2000, text: "以"),
                              Word(startMs: 3000, endMs: 3500, text: "很"),
                              Word(startMs: 3500, endMs: 4000, text: "长")]),
        ])
        let p = LyricSyncEngine.locate(positionMs: 2500, in: lyrics)
        XCTAssertEqual(p.lineIndex, 0)
        XCTAssertEqual(p.activeWordIndex, 1)
        XCTAssertEqual(p.wordProgress, 1.0, accuracy: 0.001)
    }

    /// 行已开始但第一个字还没开始:应为第一个字、进度 0,不提前点亮。
    func test_beforeFirstWordInLine_startsAtFirstWordZero() {
        let lyrics = Lyrics(lines: [
            LyricLine(startMs: 1000, endMs: 3000, text: "你好",
                      words: [Word(startMs: 1500, endMs: 2000, text: "你"),
                              Word(startMs: 2000, endMs: 3000, text: "好")]),
        ])
        let p = LyricSyncEngine.locate(positionMs: 1200, in: lyrics)
        XCTAssertEqual(p.lineIndex, 0)
        XCTAssertEqual(p.activeWordIndex, 0)
        XCTAssertEqual(p.wordProgress, 0, accuracy: 0.001)
    }

    func test_emptyLyrics_noHighlight() {
        let p = LyricSyncEngine.locate(positionMs: 1000, in: Lyrics(lines: []))
        XCTAssertEqual(p, .none)
    }
}
