import XCTest
@testable import VanessaCore

final class LyricsParserTests: XCTestCase {
    func test_emptyInput_returnsEmpty() {
        XCTAssertTrue(LyricsParser.parse(lrc: nil, yrc: nil).isEmpty)
        XCTAssertTrue(LyricsParser.parse(lrc: "", yrc: "").isEmpty)
    }

    func test_lrc_basic_parsesTimeAndText() {
        let lrc = "[00:01.00]第一行\n[00:03.50]第二行\n"
        let r = LyricsParser.parse(lrc: lrc, yrc: nil)
        XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(r.lines[0].startMs, 1000)
        XCTAssertEqual(r.lines[0].text, "第一行")
        XCTAssertEqual(r.lines[0].endMs, 3500)
        XCTAssertEqual(r.lines[1].startMs, 3500)
        XCTAssertTrue(r.lines[0].words.isEmpty)
    }

    func test_lrc_offsetTag_shiftsAllTimes() {
        let lrc = "[offset:500]\n[00:02.00]行\n"
        let r = LyricsParser.parse(lrc: lrc, yrc: nil)
        XCTAssertEqual(r.lines.first?.startMs, 1500)
    }

    func test_lrc_ignoresMetadataAndCollapsesSpaces() {
        let lrc = "[ti:标题]\n[ar:歌手]\n[00:00.00]   多   空格   \n"
        let r = LyricsParser.parse(lrc: lrc, yrc: nil)
        XCTAssertEqual(r.lines.count, 1)
        XCTAssertEqual(r.lines[0].text, "多 空格")
    }

    func test_lrc_multipleTimestampsOnOneLine() {
        let lrc = "[00:01.00][00:05.00]副歌\n"
        let r = LyricsParser.parse(lrc: lrc, yrc: nil)
        XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(r.lines.map { $0.startMs }, [1000, 5000])
        XCTAssertEqual(r.lines[0].text, "副歌")
    }

    func test_lrc_malformedLinesAreSkipped() {
        let lrc = "乱七八糟没有时间戳\n[00:02.00]有效\n[xx:yy]坏戳\n"
        let r = LyricsParser.parse(lrc: lrc, yrc: nil)
        XCTAssertEqual(r.lines.count, 1)
        XCTAssertEqual(r.lines[0].text, "有效")
    }

    func test_yrc_parsesWordsWithAbsoluteTiming() {
        // 行头 [行起点ms,行时长ms];随后每个 (字起点ms,字时长ms,0)文字
        let yrc = "[1000,2000](1000,500,0)我(1500,500,0)爱(2000,1000,0)你\n"
        let r = LyricsParser.parse(lrc: nil, yrc: yrc)
        XCTAssertEqual(r.lines.count, 1)
        let line = r.lines[0]
        XCTAssertEqual(line.startMs, 1000)
        XCTAssertEqual(line.text, "我爱你")
        XCTAssertEqual(line.words.count, 3)
        XCTAssertEqual(line.words[0], Word(startMs: 1000, endMs: 1500, text: "我"))
        XCTAssertEqual(line.words[2], Word(startMs: 2000, endMs: 3000, text: "你"))
    }

    func test_yrc_preferredOverLrcWhenBothPresent() {
        let lrc = "[00:01.00]整行\n"
        let yrc = "[1000,500](1000,500,0)字\n"
        let r = LyricsParser.parse(lrc: lrc, yrc: yrc)
        XCTAssertFalse(r.lines[0].words.isEmpty) // 用了 yrc
    }

    func test_yrc_malformedLineFallsBackGracefully() {
        let yrc = "这行不是yrc\n[2000,500](2000,500,0)好\n"
        let r = LyricsParser.parse(lrc: nil, yrc: yrc)
        XCTAssertEqual(r.lines.count, 1)
        XCTAssertEqual(r.lines[0].text, "好")
    }

    func test_tlyric_attachesTranslationByTimestamp() {
        let lrc = "[00:01.00]Hello\n[00:05.00]World\n"
        let tlyric = "[00:01.00]你好\n[00:05.00]世界\n"
        let r = LyricsParser.parse(lrc: lrc, yrc: nil, tlyric: tlyric)
        XCTAssertEqual(r.lines.map { $0.translation }, ["你好", "世界"])
    }

    func test_tlyric_matchesYrcLineWithinTolerance() {
        // yrc 行起点与译文时间戳差 300ms,仍应挂上
        let yrc = "[1300,1000](1300,1000,0)Hi\n"
        let tlyric = "[00:01.00]嗨\n"
        let r = LyricsParser.parse(lrc: nil, yrc: yrc, tlyric: tlyric)
        XCTAssertEqual(r.lines.first?.translation, "嗨")
    }

    func test_tlyric_beyondToleranceOrEmpty_isNil() {
        let lrc = "[00:01.00]A\n[00:10.00]B\n[00:20.00]\n"
        let tlyric = "[00:05.00]太远\n[00:10.00]\n[00:20.00]间奏\n"
        let r = LyricsParser.parse(lrc: lrc, yrc: nil, tlyric: tlyric)
        XCTAssertNil(r.lines[0].translation)   // 差 4s,超出容差
        XCTAssertNil(r.lines[1].translation)   // 译文为空行
        XCTAssertNil(r.lines[2].translation)   // 原文空行(间奏)不挂译文
    }

    func test_tlyric_appliesLrcOffset() {
        let lrc = "[offset:500]\n[00:02.00]行\n"
        let tlyric = "[00:02.00]译\n"
        let r = LyricsParser.parse(lrc: lrc, yrc: nil, tlyric: tlyric)
        XCTAssertEqual(r.lines.first?.startMs, 1500)
        XCTAssertEqual(r.lines.first?.translation, "译")
    }
}
