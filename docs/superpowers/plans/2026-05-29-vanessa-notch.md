# Vanessa-Notch 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 逐任务执行本计划。所有步骤用 checkbox(`- [ ]`)语法跟踪。

**Goal:** 用原生 Swift Package 构建一个 macOS 菜单栏后台 App,在刘海周围实时显示网易云当前歌曲的逐字卡拉OK歌词。

**Architecture:** 单一 SPM 包,分四个 target:`VanessaCore`(纯逻辑库,数据模型 + LyricsParser/SongMatcher/LyricSyncEngine/PlaybackClock,可被 `swift test` 完整覆盖)、`VanessaNetease`(URLSession 网络层 + 仓储 + 缓存,依赖 Core)、`VanessaApp`(AppKit/SwiftUI 库:Provider/NotchWindowController/AppState/视图,依赖 Core + Netease)、`vanessa-notch`(极薄可执行壳,只负责启动)。`.app` bundle 由 `Scripts/build-app.sh` 组装,写入 `LSUIElement=YES` 并内嵌 mediaremote-adapter。

**Tech Stack:** Swift 6 / SwiftPM、SwiftUI + AppKit、URLSession、XCTest(纯函数单测 + URLProtocol 打桩)、[`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)(perl 脚本 + 私有 framework,流式输出 NowPlaying JSON)。

**适用平台说明:** 设计文档目标 macOS 13+;开发机为 macOS 15.7,正是 15.4+ entitlement 限制场景,因此 adapter 集成是必需路径。

---

## 单位与类型约定(全计划统一,先读这一段)

- **歌词时间**:一律用毫秒 `Int`(`startMs` / `endMs`)。
- **播放进度**:`NowPlayingState` 内用秒 `TimeInterval`(与 MediaRemote 的 `elapsedTime` 一致);`PlaybackClock.positionMs(at:)` 在边界处统一转换成毫秒 `Double` 输出给歌词层。
- **歌曲 ID**:`Int64`。
- 所有跨 target 暴露的类型/方法均为 `public`;模型实现 `Equatable` 以便测试断言与 SwiftUI diff。

## 目标文件结构(决策已锁定)

```
Package.swift
Sources/
  VanessaCore/
    Models/NowPlayingState.swift      # 正在播放状态模型
    Models/Lyrics.swift               # Lyrics/LyricLine/Word/LyricPosition 模型
    LyricsParser.swift                # LRC + YRC -> Lyrics(纯函数)
    SongMatcher.swift                 # 搜索候选 -> 最匹配歌曲(纯函数)
    LyricSyncEngine.swift             # 毫秒位置 -> LyricPosition(纯函数)
    PlaybackClock.swift               # 进度+倍速 -> 实时毫秒位置(纯结构体)
  VanessaNetease/
    NeteaseAPIClient.swift            # 搜索 / 歌词两个网易云接口封装
    NeteaseLyricsRepository.swift     # 编排搜索->选歌->歌词->缓存
    LyricsCache.swift                 # 内存 + 磁盘缓存(按歌曲 ID)
  VanessaApp/
    NowPlayingProvider.swift          # 协议 + AdapterEventDecoder(纯解码)
    MediaRemoteNowPlayingProvider.swift # 进程化 adapter,吐状态流
    NotchGeometry.swift               # 屏幕几何 -> 窗口 frame(纯函数)
    NotchWindowController.swift       # 置顶透明窗口创建/定位/多屏/降级
    AppState.swift                    # 编排所有模块,输出 AppUIState
    Views/PlayingPanelView.swift      # 播放面板(封面+音频条+逐字歌词)
    Views/IdlePillView.swift          # 空闲胶囊
    Views/SettingsView.swift          # 设置弹窗
    AppDelegate.swift                 # NSApplication 装配 + 状态项
  vanessa-notch/
    main.swift                        # 启动入口
Tests/
  VanessaCoreTests/{LyricsParserTests,SongMatcherTests,LyricSyncEngineTests,PlaybackClockTests}.swift
  VanessaNeteaseTests/{NeteaseAPIClientTests,NeteaseLyricsRepositoryTests}.swift
  VanessaAppTests/{AdapterEventDecoderTests,NotchGeometryTests,AppStateTests}.swift
Scripts/build-app.sh                  # 组装 .app bundle(LSUIElement + 内嵌 adapter)
Resources/Info.plist                  # App bundle 的 Info.plist 模板
```

文件按职责切分:纯逻辑全部进 `VanessaCore`,网络与缓存进 `VanessaNetease`,所有 AppKit/SwiftUI/进程副作用进 `VanessaApp`。可执行 target `vanessa-notch` 只放 `main.swift`,因此 `VanessaApp` 能被测试 target `@testable import`。

---

## Phase 0:工程脚手架

### Task 0:创建 SPM 包骨架并跑通空测试

**Files:**
- Create: `Package.swift`
- Create: `Sources/VanessaCore/VanessaCore.swift`
- Create: `Tests/VanessaCoreTests/SmokeTests.swift`
- Create: `.gitignore`(追加 `.build/`)

- [ ] **Step 1:写 `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VanessaNotch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vanessa-notch", targets: ["vanessa-notch"]),
    ],
    targets: [
        .target(name: "VanessaCore"),
        .target(name: "VanessaNetease", dependencies: ["VanessaCore"]),
        .target(name: "VanessaApp", dependencies: ["VanessaCore", "VanessaNetease"]),
        .executableTarget(name: "vanessa-notch", dependencies: ["VanessaApp"]),
        .testTarget(name: "VanessaCoreTests", dependencies: ["VanessaCore"]),
        .testTarget(name: "VanessaNeteaseTests", dependencies: ["VanessaNetease"]),
        .testTarget(name: "VanessaAppTests", dependencies: ["VanessaApp"]),
    ]
)
```

- [ ] **Step 2:写占位源文件,保证各 target 非空**

`Sources/VanessaCore/VanessaCore.swift`:
```swift
// VanessaCore:纯逻辑库占位,后续任务填充具体类型。
public enum VanessaCore {
    /// 库版本号,仅用于占位与冒烟测试。
    public static let version = "0.0.1"
}
```

为让包能编译,先放占位入口(后续 Phase 5 替换):
`Sources/VanessaApp/AppDelegate.swift`:
```swift
// 占位:Phase 4/5 会替换为真正的 NSApplicationDelegate 装配。
public enum VanessaApp {
    public static let bootstrapped = true
}
```
`Sources/VanessaNetease/NeteaseAPIClient.swift`:
```swift
// 占位:Phase 2 填充。
enum VanessaNeteasePlaceholder {}
```
`Sources/vanessa-notch/main.swift`:
```swift
// 占位:Phase 5 替换为真正的启动逻辑。
import VanessaApp
_ = VanessaApp.bootstrapped
```

- [ ] **Step 3:写冒烟测试**

`Tests/VanessaCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import VanessaCore

final class SmokeTests: XCTestCase {
    func test_version_isNotEmpty() {
        XCTAssertFalse(VanessaCore.version.isEmpty)
    }
}
```

- [ ] **Step 4:运行测试,确认通过**

Run: `swift test`
Expected: 编译通过,`SmokeTests` 全绿(1 test passed)。

- [ ] **Step 5:提交**

```bash
printf '\n.build/\n*.xcodeproj\n.DS_Store\n' >> .gitignore
git add Package.swift Sources Tests .gitignore
git commit -m "chore: 初始化 VanessaNotch SPM 包骨架"
```

---

## Phase 1:数据模型与纯函数核心(VanessaCore)

### Task 1:核心数据模型

**Files:**
- Create: `Sources/VanessaCore/Models/NowPlayingState.swift`
- Create: `Sources/VanessaCore/Models/Lyrics.swift`
- Test: `Tests/VanessaCoreTests/ModelsTests.swift`

- [ ] **Step 1:写失败测试**

`Tests/VanessaCoreTests/ModelsTests.swift`:
```swift
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
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter ModelsTests`
Expected: FAIL —「cannot find 'NowPlayingState' in scope」。

- [ ] **Step 3:写 `NowPlayingState`**

`Sources/VanessaCore/Models/NowPlayingState.swift`:
```swift
import Foundation

/// 正在播放状态快照。来自 MediaRemote(经 adapter)的一次采样。
/// duration/elapsed 单位为秒(与 MediaRemote 的 elapsedTime 一致)。
public struct NowPlayingState: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var artworkData: Data?
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var sampledAt: Date
    public var rate: Double
    public var isPlaying: Bool
    public var sourceBundleID: String

    public init(title: String, artist: String, album: String, artworkData: Data?,
                duration: TimeInterval, elapsed: TimeInterval, sampledAt: Date,
                rate: Double, isPlaying: Bool, sourceBundleID: String) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.duration = duration
        self.elapsed = elapsed
        self.sampledAt = sampledAt
        self.rate = rate
        self.isPlaying = isPlaying
        self.sourceBundleID = sourceBundleID
    }

    /// 用于判断「是否换歌」的身份指纹(标题+歌手+来源)。
    public var songIdentity: String { "\(sourceBundleID)|\(title)|\(artist)" }
}
```

- [ ] **Step 4:写 `Lyrics` 模型族**

`Sources/VanessaCore/Models/Lyrics.swift`:
```swift
import Foundation

/// 逐字片段(YRC 中的一个字/词)。
public struct Word: Equatable, Sendable {
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public init(startMs: Int, endMs: Int, text: String) {
        self.startMs = startMs; self.endMs = endMs; self.text = text
    }
}

/// 一行歌词。words 为空表示该行无逐字信息(只能整行高亮)。
public struct LyricLine: Equatable, Sendable {
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var words: [Word]
    public init(startMs: Int, endMs: Int, text: String, words: [Word]) {
        self.startMs = startMs; self.endMs = endMs; self.text = text; self.words = words
    }
}

/// 统一歌词模型。
public struct Lyrics: Equatable, Sendable {
    public var lines: [LyricLine]
    public init(lines: [LyricLine]) { self.lines = lines }
    /// 无任何可用行时为空。
    public var isEmpty: Bool { lines.isEmpty }
}

/// 同步引擎输出:当前应高亮到哪。
public struct LyricPosition: Equatable, Sendable {
    /// 当前行索引;nil 表示在首行之前 / 无歌词。
    public var lineIndex: Int?
    /// 当前激活的逐字索引;nil 表示该行无逐字或尚未进入任何字。
    public var activeWordIndex: Int?
    /// 当前字内进度 0...1。
    public var wordProgress: Double
    /// 整行进度 0...1(无逐字信息时的回退高亮依据)。
    public var lineProgress: Double
    public init(lineIndex: Int?, activeWordIndex: Int?, wordProgress: Double, lineProgress: Double) {
        self.lineIndex = lineIndex; self.activeWordIndex = activeWordIndex
        self.wordProgress = wordProgress; self.lineProgress = lineProgress
    }
    /// 无高亮(首行前/无歌词)。
    public static let none = LyricPosition(lineIndex: nil, activeWordIndex: nil, wordProgress: 0, lineProgress: 0)
}
```

- [ ] **Step 5:运行测试确认通过**

Run: `swift test --filter ModelsTests`
Expected: PASS。

- [ ] **Step 6:提交**

```bash
git add Sources/VanessaCore/Models Tests/VanessaCoreTests/ModelsTests.swift
git commit -m "feat(core): 核心数据模型 NowPlayingState/Lyrics/LyricPosition"
```

---

### Task 2:LyricsParser —— 解析 LRC

**Files:**
- Create: `Sources/VanessaCore/LyricsParser.swift`
- Test: `Tests/VanessaCoreTests/LyricsParserTests.swift`

- [ ] **Step 1:写失败测试(LRC 基础 + offset + 多空格 + 畸形 + 空)**

`Tests/VanessaCoreTests/LyricsParserTests.swift`:
```swift
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
        // 行尾时间 = 下一行起点
        XCTAssertEqual(r.lines[0].endMs, 3500)
        XCTAssertEqual(r.lines[1].startMs, 3500)
        XCTAssertTrue(r.lines[0].words.isEmpty)
    }

    func test_lrc_offsetTag_shiftsAllTimes() {
        // offset 正值表示歌词提前(整体时间减少),网易云约定:实际时间 = 标签时间 - offset
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
}
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter LyricsParserTests`
Expected: FAIL —「cannot find 'LyricsParser' in scope」。

- [ ] **Step 3:实现 `LyricsParser`(本任务只实现 LRC + offset;YRC 在 Task 3 补)**

`Sources/VanessaCore/LyricsParser.swift`:
```swift
import Foundation

/// LRC + YRC 歌词解析器(纯函数,无副作用)。
public enum LyricsParser {
    /// 解析入口:有 yrc 优先用逐字,否则用 lrc。offset 标签(若有)统一应用。
    /// - Returns: 统一歌词模型;无任何有效行时 lines 为空。
    public static func parse(lrc: String?, yrc: String?) -> Lyrics {
        let offset = lrc.flatMap(parseOffset) ?? 0
        if let yrc, !yrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = parseYRC(yrc).map { shift($0, by: offset) }
            if !lines.isEmpty { return finalize(lines) }
        }
        guard let lrc else { return Lyrics(lines: []) }
        let lines = parseLRC(lrc).map { shift($0, by: offset) }
        return finalize(lines)
    }

    /// 从 [offset:xxx] 标签解析整体偏移毫秒(网易云约定:实际时间 = 标签时间 - offset)。
    static func parseOffset(_ lrc: String) -> Int? {
        guard let range = lrc.range(of: #"\[offset:\s*(-?\d+)\s*\]"#, options: .regularExpression) else { return nil }
        let token = lrc[range]
        let digits = token.filter { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    /// 解析全部 LRC 行;一行可含多个时间戳,会展开成多行。元数据/无戳行跳过。
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let stamps = timestamps(in: line)
            guard !stamps.isEmpty else { continue }
            let text = collapseSpaces(stripStamps(line))
            for ms in stamps {
                result.append(LyricLine(startMs: ms, endMs: ms, text: text, words: []))
            }
        }
        return result.sorted { $0.startMs < $1.startMs }
    }

    /// 提取一行里所有 [mm:ss.xx] / [mm:ss.xxx] 时间戳(毫秒)。元数据标签(非数字冒号格式)返回空。
    static func timestamps(in line: String) -> [Int] {
        let pattern = #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = line as NSString
        let matches = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
        return matches.map { m in
            let mm = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let ss = Int(ns.substring(with: m.range(at: 2))) ?? 0
            var frac = 0
            if m.range(at: 3).location != NSNotFound {
                let f = ns.substring(with: m.range(at: 3))
                // 补齐到毫秒:两位当百分秒,三位当毫秒
                frac = (f.count == 2) ? (Int(f) ?? 0) * 10 : (Int(f.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0)
            }
            return (mm * 60 + ss) * 1000 + frac
        }
    }

    /// 去掉行首所有 [..] 标签,保留正文。
    static func stripStamps(_ line: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\[[^\]]*\]"#) else { return line }
        let ns = line as NSString
        return re.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    /// 合并连续空白并去首尾空格。
    static func collapseSpaces(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// 整行时间平移 -offset(见 parseOffset 约定)。
    static func shift(_ line: LyricLine, by offset: Int) -> LyricLine {
        guard offset != 0 else { return line }
        return LyricLine(startMs: line.startMs - offset,
                         endMs: line.endMs - offset,
                         text: line.text,
                         words: line.words.map { Word(startMs: $0.startMs - offset, endMs: $0.endMs - offset, text: $0.text) })
    }

    /// 收尾:按起点排序,推算每行 endMs(= 下一行起点;最后一行保留自身 endMs 或 +4s 兜底)。
    static func finalize(_ lines: [LyricLine]) -> Lyrics {
        let sorted = lines.sorted { $0.startMs < $1.startMs }
        guard !sorted.isEmpty else { return Lyrics(lines: []) }
        var out = sorted
        for i in out.indices {
            if i + 1 < out.count {
                out[i].endMs = out[i + 1].startMs
            } else if out[i].endMs <= out[i].startMs {
                out[i].endMs = out[i].startMs + 4000
            }
        }
        return Lyrics(lines: out)
    }

    /// YRC 解析占位,Task 3 实现。
    static func parseYRC(_ yrc: String) -> [LyricLine] { [] }
}
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter LyricsParserTests`
Expected: PASS(6 tests)。

- [ ] **Step 5:提交**

```bash
git add Sources/VanessaCore/LyricsParser.swift Tests/VanessaCoreTests/LyricsParserTests.swift
git commit -m "feat(core): LyricsParser 支持 LRC/offset/多戳/畸形跳过"
```

---

### Task 3:LyricsParser —— 解析 YRC(逐字)

**Files:**
- Modify: `Sources/VanessaCore/LyricsParser.swift`(替换 `parseYRC` 占位实现)
- Test: `Tests/VanessaCoreTests/LyricsParserTests.swift`(追加 YRC 用例)

- [ ] **Step 1:追加失败测试**

在 `LyricsParserTests` 中追加:
```swift
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
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter LyricsParserTests`
Expected: FAIL —`test_yrc_*` 三例失败(parseYRC 返回空)。

- [ ] **Step 3:替换 `parseYRC` 实现**

把 `LyricsParser.swift` 末尾的占位:
```swift
    /// YRC 解析占位,Task 3 实现。
    static func parseYRC(_ yrc: String) -> [LyricLine] { [] }
```
替换为:
```swift
    /// 解析 YRC 逐字歌词。行格式:`[start,duration](ws,wd,0)字(ws,wd,0)字...`。
    /// 无法识别为 yrc 行头的行直接跳过。
    static func parseYRC(_ yrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let headerRe = try? NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
        let wordRe = try? NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)([^\(\[]*)"#)
        for raw in yrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let ns = line as NSString
            guard let headerRe,
                  let head = headerRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let lineStart = Int(ns.substring(with: head.range(at: 1))) ?? 0
            let lineDur = Int(ns.substring(with: head.range(at: 2))) ?? 0
            var words: [Word] = []
            var text = ""
            if let wordRe {
                let body = ns.substring(from: head.range.length) as NSString
                for m in wordRe.matches(in: body as String, range: NSRange(location: 0, length: body.length)) {
                    let ws = Int(body.substring(with: m.range(at: 1))) ?? 0
                    let wd = Int(body.substring(with: m.range(at: 2))) ?? 0
                    let t = body.substring(with: m.range(at: 3))
                    words.append(Word(startMs: ws, endMs: ws + wd, text: t))
                    text += t
                }
            }
            if words.isEmpty { continue } // 行头有但无有效字,跳过
            result.append(LyricLine(startMs: lineStart, endMs: lineStart + lineDur,
                                    text: collapseSpaces(text), words: words))
        }
        return result
    }
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter LyricsParserTests`
Expected: PASS(9 tests)。

- [ ] **Step 5:提交**

```bash
git add Sources/VanessaCore/LyricsParser.swift Tests/VanessaCoreTests/LyricsParserTests.swift
git commit -m "feat(core): LyricsParser 支持 YRC 逐字解析,优先于 LRC"
```

---

### Task 4:SongMatcher —— 从搜索候选中选最匹配

**Files:**
- Create: `Sources/VanessaCore/SongMatcher.swift`
- Test: `Tests/VanessaCoreTests/SongMatcherTests.swift`

- [ ] **Step 1:写失败测试(归一化 / 时长容差 / feat. / 无匹配)**

`Tests/VanessaCoreTests/SongMatcherTests.swift`:
```swift
import XCTest
@testable import VanessaCore

final class SongMatcherTests: XCTestCase {
    private func cand(_ id: Int64, _ t: String, _ a: [String], _ d: Int) -> SongCandidate {
        SongCandidate(id: id, title: t, artists: a, durationMs: d)
    }

    func test_exactMatch_wins() {
        let q = SongQuery(title: "晴天", artist: "周杰伦", durationMs: 269000)
        let c = [cand(1, "晴天", ["周杰伦"], 269000), cand(2, "雨天", ["林俊杰"], 200000)]
        XCTAssertEqual(SongMatcher.bestMatch(for: q, in: c)?.id, 1)
    }

    func test_durationToleranceFiltersFarCandidates() {
        let q = SongQuery(title: "歌", artist: "人", durationMs: 200000)
        // 标题歌手都一样,但一个时长差 30s(超容差),一个差 1s
        let c = [cand(1, "歌", ["人"], 230000), cand(2, "歌", ["人"], 201000)]
        XCTAssertEqual(SongMatcher.bestMatch(for: q, in: c, durationToleranceMs: 5000)?.id, 2)
    }

    func test_normalizesCasePunctuationAndFeat() {
        let q = SongQuery(title: "Hello (Live)", artist: "Adele feat. someone", durationMs: 100000)
        let c = [cand(1, "hello", ["Adele"], 100500)]
        XCTAssertEqual(SongMatcher.bestMatch(for: q, in: c)?.id, 1)
    }

    func test_noConfidentMatch_returnsNil() {
        let q = SongQuery(title: "完全不同的歌名ABC", artist: "某人", durationMs: 100000)
        let c = [cand(1, "毫不相干XYZ", ["另一个人"], 500000)]
        XCTAssertNil(SongMatcher.bestMatch(for: q, in: c))
    }

    func test_emptyCandidates_returnsNil() {
        let q = SongQuery(title: "x", artist: "y", durationMs: 1000)
        XCTAssertNil(SongMatcher.bestMatch(for: q, in: []))
    }
}
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter SongMatcherTests`
Expected: FAIL —「cannot find 'SongMatcher' / 'SongCandidate' / 'SongQuery'」。

- [ ] **Step 3:实现 `SongMatcher`**

`Sources/VanessaCore/SongMatcher.swift`:
```swift
import Foundation

/// 搜索接口返回的候选歌曲(已抽取成与网络无关的纯模型)。
public struct SongCandidate: Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let artists: [String]
    public let durationMs: Int
    public init(id: Int64, title: String, artists: [String], durationMs: Int) {
        self.id = id; self.title = title; self.artists = artists; self.durationMs = durationMs
    }
}

/// 选歌查询条件(来自 NowPlaying)。
public struct SongQuery: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let durationMs: Int
    public init(title: String, artist: String, durationMs: Int) {
        self.title = title; self.artist = artist; self.durationMs = durationMs
    }
}

/// 纯函数选歌器:综合标题/歌手相似度与时长接近度打分,低置信度返回 nil。
public enum SongMatcher {
    /// 选出最匹配候选。
    /// - Parameter durationToleranceMs: 时长容差;超过容差的候选时长得分归零(但不直接淘汰,标题歌手极像仍可能入选)。
    /// - Returns: 最高分候选;若最高分 < 0.5 或时长差超容差,返回 nil(交由上层降级显示「歌名-歌手」)。
    public static func bestMatch(for query: SongQuery, in candidates: [SongCandidate],
                                 durationToleranceMs: Int = 5000) -> SongCandidate? {
        let qTitle = normalize(query.title)
        let qArtist = normalize(query.artist)
        var best: (cand: SongCandidate, score: Double, durOK: Bool)?
        for c in candidates {
            let titleSim = similarity(qTitle, normalize(c.title))
            let artistSim = c.artists.map { similarity(qArtist, normalize($0)) }.max() ?? 0
            let durDiff = abs(c.durationMs - query.durationMs)
            let durOK = durDiff <= durationToleranceMs
            let durSim = durOK ? (1 - Double(durDiff) / Double(max(durationToleranceMs, 1))) : 0
            let score = 0.6 * titleSim + 0.25 * artistSim + 0.15 * durSim
            if best == nil || score > best!.score { best = (c, score, durOK) }
        }
        guard let b = best, b.score >= 0.5, b.durOK else { return nil }
        return b.cand
    }

    /// 归一化:小写、去括号内容、去 feat. 之后、去非字母数字(保留中日韩)、压空格。
    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        t = t.replacingOccurrences(of: #"[\(\（\[].*?[\)\）\]]"#, with: "", options: .regularExpression) // 去括号块
        t = t.replacingOccurrences(of: #"(feat\.?|ft\.?|featuring).*$"#, with: "", options: [.regularExpression]) // 去 feat
        t = t.replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression) // 仅留字母数字与文字
        return t
    }

    /// 归一化 Levenshtein 相似度,0...1。
    static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1 }
        return 1 - Double(levenshtein(Array(a), Array(b))) / Double(maxLen)
    }

    /// 标准编辑距离(动态规划,滚动数组)。
    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter SongMatcherTests`
Expected: PASS(5 tests)。

- [ ] **Step 5:提交**

```bash
git add Sources/VanessaCore/SongMatcher.swift Tests/VanessaCoreTests/SongMatcherTests.swift
git commit -m "feat(core): SongMatcher 归一化+时长容差选歌,低置信度返回 nil"
```

---

### Task 5:LyricSyncEngine —— 毫秒位置映射到高亮

**Files:**
- Create: `Sources/VanessaCore/LyricSyncEngine.swift`
- Test: `Tests/VanessaCoreTests/LyricSyncEngineTests.swift`

- [ ] **Step 1:写失败测试(首行前 / 行内逐字 / 行间间隙 / 末行 / 无逐字回退)**

`Tests/VanessaCoreTests/LyricSyncEngineTests.swift`:
```swift
import XCTest
@testable import VanessaCore

final class LyricSyncEngineTests: XCTestCase {
    // 两行,第一行带逐字,第二行不带
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
        XCTAssertEqual(p.activeWordIndex, 1)          // 第二个字「爱」
        XCTAssertEqual(p.wordProgress, 0.5, accuracy: 0.001)
    }

    func test_gapBetweenLines_holdsPreviousLineCompleted() {
        let p = LyricSyncEngine.locate(positionMs: 3500, in: sample())
        XCTAssertEqual(p.lineIndex, 0)                // 间隙仍停留在上一行
        XCTAssertEqual(p.activeWordIndex, 2)          // 最后一个字
        XCTAssertEqual(p.wordProgress, 1.0, accuracy: 0.001)
        XCTAssertEqual(p.lineProgress, 1.0, accuracy: 0.001)
    }

    func test_lineWithoutWords_usesLineProgress() {
        let p = LyricSyncEngine.locate(positionMs: 5000, in: sample())
        XCTAssertEqual(p.lineIndex, 1)
        XCTAssertNil(p.activeWordIndex)
        XCTAssertEqual(p.lineProgress, 0.5, accuracy: 0.001) // (5000-4000)/(6000-4000)
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
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter LyricSyncEngineTests`
Expected: FAIL —「cannot find 'LyricSyncEngine'」。

- [ ] **Step 3:实现 `LyricSyncEngine`**

`Sources/VanessaCore/LyricSyncEngine.swift`:
```swift
import Foundation

/// 纯函数同步引擎:把实时毫秒位置映射成「当前行 + 当前字进度」。
public enum LyricSyncEngine {
    /// 定位当前高亮。
    /// 规则:当前行 = 最后一个 startMs <= pos 的行(行间间隙保持上一行,直至下一行开始)。
    public static func locate(positionMs pos: Double, in lyrics: Lyrics) -> LyricPosition {
        guard !lyrics.lines.isEmpty else { return .none }
        let posI = Int(pos)
        // 首行之前:无高亮
        guard posI >= lyrics.lines[0].startMs else { return .none }

        // 找最后一个 startMs <= pos 的行索引
        var idx = 0
        for (i, line) in lyrics.lines.enumerated() where line.startMs <= posI { idx = i }
        let line = lyrics.lines[idx]

        let lineSpan = max(line.endMs - line.startMs, 1)
        let lineProgress = clamp01(Double(posI - line.startMs) / Double(lineSpan))

        // 无逐字:只给整行进度
        guard !line.words.isEmpty else {
            return LyricPosition(lineIndex: idx, activeWordIndex: nil, wordProgress: 0, lineProgress: lineProgress)
        }

        // 行已唱完(pos 越过本行 endMs,处于间隙或末行之后):最后一个字置满
        if posI >= line.endMs {
            return LyricPosition(lineIndex: idx, activeWordIndex: line.words.count - 1,
                                 wordProgress: 1, lineProgress: 1)
        }
        // 找激活字
        for (wi, w) in line.words.enumerated() {
            if posI < w.startMs {
                // 尚未进入任何字(行首到首字之间):无激活字,仅行进度
                return LyricPosition(lineIndex: idx, activeWordIndex: nil, wordProgress: 0, lineProgress: lineProgress)
            }
            if posI < w.endMs {
                let span = max(w.endMs - w.startMs, 1)
                let wp = clamp01(Double(posI - w.startMs) / Double(span))
                return LyricPosition(lineIndex: idx, activeWordIndex: wi, wordProgress: wp, lineProgress: lineProgress)
            }
        }
        // 落在最后一个字之后但仍 < endMs:置满最后一个字
        return LyricPosition(lineIndex: idx, activeWordIndex: line.words.count - 1,
                             wordProgress: 1, lineProgress: lineProgress)
    }

    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter LyricSyncEngineTests`
Expected: PASS(6 tests)。

- [ ] **Step 5:提交**

```bash
git add Sources/VanessaCore/LyricSyncEngine.swift Tests/VanessaCoreTests/LyricSyncEngineTests.swift
git commit -m "feat(core): LyricSyncEngine 行/字定位,间隙保持上一行"
```

---

### Task 6:PlaybackClock —— 由进度+倍速推算实时位置

**Files:**
- Create: `Sources/VanessaCore/PlaybackClock.swift`
- Test: `Tests/VanessaCoreTests/PlaybackClockTests.swift`

- [ ] **Step 1:写失败测试(倍速 / 暂停 / 漂移 / 越界 clamp)**

`Tests/VanessaCoreTests/PlaybackClockTests.swift`:
```swift
import XCTest
import Foundation
@testable import VanessaCore

final class PlaybackClockTests: XCTestCase {
    private func state(elapsed: TimeInterval, rate: Double, playing: Bool,
                       duration: TimeInterval = 300, at t: TimeInterval = 1000) -> NowPlayingState {
        NowPlayingState(title: "t", artist: "a", album: "", artworkData: nil,
                        duration: duration, elapsed: elapsed,
                        sampledAt: Date(timeIntervalSince1970: t),
                        rate: rate, isPlaying: playing, sourceBundleID: "x")
    }

    func test_playingRate1_advancesWithWallClock() {
        let clock = PlaybackClock(state: state(elapsed: 10, rate: 1, playing: true, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 1003)) // 过了 3 秒
        XCTAssertEqual(pos, 13000, accuracy: 1)
    }

    func test_rate1_5_advancesFaster() {
        let clock = PlaybackClock(state: state(elapsed: 10, rate: 1.5, playing: true, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 1002)) // 2 秒 * 1.5 = 3 秒
        XCTAssertEqual(pos, 13000, accuracy: 1)
    }

    func test_paused_doesNotAdvance() {
        let clock = PlaybackClock(state: state(elapsed: 42, rate: 1, playing: false, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 9999))
        XCTAssertEqual(pos, 42000, accuracy: 1)
    }

    func test_clampsToDuration() {
        let clock = PlaybackClock(state: state(elapsed: 295, rate: 1, playing: true, duration: 300, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 1100)) // 远超时长
        XCTAssertEqual(pos, 300000, accuracy: 1)
    }

    func test_negativeDrift_clampsToZero() {
        // now 早于 sampledAt(时钟漂移),不应为负
        let clock = PlaybackClock(state: state(elapsed: 5, rate: 1, playing: true, at: 1000))
        let pos = clock.positionMs(at: Date(timeIntervalSince1970: 990))
        XCTAssertEqual(pos, 5000, accuracy: 1) // delta 截断为 0
    }
}
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter PlaybackClockTests`
Expected: FAIL —「cannot find 'PlaybackClock'」。

- [ ] **Step 3:实现 `PlaybackClock`**

`Sources/VanessaCore/PlaybackClock.swift`:
```swift
import Foundation

/// 由一次 NowPlaying 采样推算任意时刻的实时播放位置(毫秒)。值类型,纯计算。
public struct PlaybackClock: Equatable, Sendable {
    public let elapsed: TimeInterval     // 采样时刻的进度(秒)
    public let sampledAt: Date           // 采样时刻
    public let rate: Double              // 播放倍速
    public let isPlaying: Bool
    public let duration: TimeInterval    // 总时长(秒)

    public init(elapsed: TimeInterval, sampledAt: Date, rate: Double, isPlaying: Bool, duration: TimeInterval) {
        self.elapsed = elapsed; self.sampledAt = sampledAt; self.rate = rate
        self.isPlaying = isPlaying; self.duration = duration
    }

    /// 从 NowPlaying 采样构造。
    public init(state: NowPlayingState) {
        self.init(elapsed: state.elapsed, sampledAt: state.sampledAt,
                  rate: state.rate, isPlaying: state.isPlaying, duration: state.duration)
    }

    /// 计算给定时刻的实时位置(毫秒)。
    /// 暂停时停在采样进度;播放时按 (now - sampledAt) * rate 前进;负漂移截断为 0;越界 clamp 到 [0, duration]。
    public func positionMs(at now: Date) -> Double {
        let delta = isPlaying ? max(0, now.timeIntervalSince(sampledAt)) * rate : 0
        let secs = min(max(0, elapsed + delta), duration)
        return secs * 1000
    }
}
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter PlaybackClockTests`
Expected: PASS(5 tests)。

- [ ] **Step 5:全量回归 + 提交**

Run: `swift test`
Expected: VanessaCore 全部测试通过。
```bash
git add Sources/VanessaCore/PlaybackClock.swift Tests/VanessaCoreTests/PlaybackClockTests.swift
git commit -m "feat(core): PlaybackClock 倍速/暂停/漂移/越界推算实时位置"
```

---

## Phase 2:网易云网络层(VanessaNetease)

> 接口为网易云**非官方**接口。本计划用 `URLProtocol` 打桩,**测试绝不打真实网络**。真实 URL 的连通性/字段变化在真机 QA 阶段核对(见 Phase 6 QA 清单)。

### Task 7:URLProtocol 打桩基础设施

**Files:**
- Create: `Tests/VanessaNeteaseTests/StubURLProtocol.swift`

- [ ] **Step 1:写打桩类(测试辅助,无需先写测试)**

`Tests/VanessaNeteaseTests/StubURLProtocol.swift`:
```swift
import Foundation

/// 测试用 URLProtocol:按「请求 URL 包含某子串」返回预置响应,断网时抛错。
final class StubURLProtocol: URLProtocol {
    struct Stub { let data: Data; let statusCode: Int; let error: Error? }
    /// 子串 -> 响应。匹配第一个被 url.absoluteString 包含的 key。
    nonisolated(unsafe) static var stubs: [String: Stub] = [:]

    static func reset() { stubs = [:] }
    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        guard let (_, stub) = StubURLProtocol.stubs.first(where: { url.contains($0.key) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error); return
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

- [ ] **Step 2:编译确认(暂无断言,确保辅助类可编)**

Run: `swift build --target VanessaNeteaseTests` 不适用(测试 target 随 `swift test` 编译)。改运行:`swift test --filter VanessaNeteaseTests`
Expected: 目前无任何测试方法,编译通过、0 tests run(若报错则修正打桩类)。

- [ ] **Step 3:提交**

```bash
git add Tests/VanessaNeteaseTests/StubURLProtocol.swift
git commit -m "test(netease): URLProtocol 打桩基础设施"
```

---

### Task 8:NeteaseAPIClient —— 搜索与歌词接口

**Files:**
- Create: `Sources/VanessaNetease/NeteaseAPIClient.swift`(替换 Phase 0 占位)
- Test: `Tests/VanessaNeteaseTests/NeteaseAPIClientTests.swift`

- [ ] **Step 1:写失败测试(用 fixture + 打桩,断网抛错)**

`Tests/VanessaNeteaseTests/NeteaseAPIClientTests.swift`:
```swift
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
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter NeteaseAPIClientTests`
Expected: FAIL —「cannot find 'NeteaseAPIClient' / 'NeteaseAPIError'」。

- [ ] **Step 3:实现 `NeteaseAPIClient`**

把 `Sources/VanessaNetease/NeteaseAPIClient.swift` 全部替换为:
```swift
import Foundation
import VanessaCore

/// 网络层错误。
public enum NeteaseAPIError: Error, Equatable {
    case badStatus(Int)
    case decoding
}

/// 歌词原始文本(未解析)。
public struct RawLyrics: Equatable, Sendable {
    public let lrc: String?
    public let yrc: String?
}

/// 封装网易云搜索 / 歌词两个非官方接口。所有网络经注入的 URLSession,便于打桩。
public struct NeteaseAPIClient: Sendable {
    private let session: URLSession
    private let baseURL: String

    /// - Parameters:
    ///   - session: 注入的会话(测试时为打桩会话)。
    ///   - baseURL: 接口基址,默认网易云公开域名。
    public init(session: URLSession = .shared, baseURL: String = "https://music.163.com/api") {
        self.session = session
        self.baseURL = baseURL
    }

    /// 搜索:用「歌名 歌手」作为关键词,返回候选列表。
    public func search(title: String, artist: String) async throws -> [SongCandidate] {
        let keywords = "\(title) \(artist)".trimmingCharacters(in: .whitespaces)
        let q = keywords.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keywords
        let url = URL(string: "\(baseURL)/search/get?s=\(q)&type=1&limit=10")!
        let data = try await get(url)
        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return decoded.result.songs.map {
                SongCandidate(id: $0.id, title: $0.name,
                              artists: $0.artists.map { $0.name }, durationMs: $0.duration)
            }
        } catch { throw NeteaseAPIError.decoding }
    }

    /// 拉取指定歌曲 ID 的 LRC + YRC 原始文本。
    public func fetchLyrics(songID: Int64) async throws -> RawLyrics {
        let url = URL(string: "\(baseURL)/song/lyric?id=\(songID)&lv=1&kv=1&yv=1")!
        let data = try await get(url)
        do {
            let decoded = try JSONDecoder().decode(LyricResponse.self, from: data)
            let lrc = decoded.lrc?.lyric.flatMap { $0.isEmpty ? nil : $0 }
            let yrc = decoded.yrc?.lyric.flatMap { $0.isEmpty ? nil : $0 }
            return RawLyrics(lrc: lrc, yrc: yrc)
        } catch { throw NeteaseAPIError.decoding }
    }

    /// GET 并校验 HTTP 状态。
    private func get(_ url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NeteaseAPIError.badStatus(http.statusCode)
        }
        return data
    }

    // MARK: - 解码模型(仅取需要的字段)
    private struct SearchResponse: Decodable {
        struct Result: Decodable { let songs: [Song] }
        struct Song: Decodable { let id: Int64; let name: String; let duration: Int; let artists: [Artist] }
        struct Artist: Decodable { let name: String }
        let result: Result
    }
    private struct LyricResponse: Decodable {
        struct Lyric: Decodable { let lyric: String? }
        let lrc: Lyric?
        let yrc: Lyric?
    }
}
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter NeteaseAPIClientTests`
Expected: PASS(5 tests)。

- [ ] **Step 5:提交**

```bash
git add Sources/VanessaNetease/NeteaseAPIClient.swift Tests/VanessaNeteaseTests/NeteaseAPIClientTests.swift
git commit -m "feat(netease): NeteaseAPIClient 搜索/歌词接口 + 解码 + 状态校验"
```

---

### Task 9:LyricsCache —— 内存 + 磁盘缓存

**Files:**
- Create: `Sources/VanessaNetease/LyricsCache.swift`
- Test: `Tests/VanessaNeteaseTests/LyricsCacheTests.swift`

- [ ] **Step 1:写失败测试(写入后命中 / 磁盘持久化 / 未命中返回 nil)**

`Tests/VanessaNeteaseTests/LyricsCacheTests.swift`:
```swift
import XCTest
import VanessaCore
@testable import VanessaNetease

final class LyricsCacheTests: XCTestCase {
    private func tmpDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vanessa-cache-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private let sample = Lyrics(lines: [LyricLine(startMs: 0, endMs: 1000, text: "hi", words: [])])

    func test_missReturnsNil() {
        let cache = LyricsCache(directory: tmpDir())
        XCTAssertNil(cache.lyrics(forSongID: 1))
    }

    func test_memoryHitAfterStore() {
        let cache = LyricsCache(directory: tmpDir())
        cache.store(sample, forSongID: 42)
        XCTAssertEqual(cache.lyrics(forSongID: 42), sample)
    }

    func test_diskPersistsAcrossInstances() {
        let dir = tmpDir()
        LyricsCache(directory: dir).store(sample, forSongID: 7)
        let fresh = LyricsCache(directory: dir) // 新实例只能从磁盘读
        XCTAssertEqual(fresh.lyrics(forSongID: 7), sample)
    }
}
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter LyricsCacheTests`
Expected: FAIL —「cannot find 'LyricsCache'」。

- [ ] **Step 3:让 `Lyrics` 族可编解码(为磁盘缓存)**

修改 `Sources/VanessaCore/Models/Lyrics.swift`,给 `Word`/`LyricLine`/`Lyrics` 三个类型的 `Equatable, Sendable` 声明追加 `Codable`:
```swift
public struct Word: Equatable, Sendable, Codable {
```
```swift
public struct LyricLine: Equatable, Sendable, Codable {
```
```swift
public struct Lyrics: Equatable, Sendable, Codable {
```
(仅在这三处协议列表追加 `, Codable`,其余不动。)

- [ ] **Step 4:实现 `LyricsCache`**

`Sources/VanessaNetease/LyricsCache.swift`:
```swift
import Foundation
import VanessaCore

/// 歌词缓存:内存字典(快)+ 磁盘 JSON(跨进程持久)。按歌曲 ID。线程安全(串行队列)。
public final class LyricsCache: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "vanessa.lyrics-cache")
    private var memory: [Int64: Lyrics] = [:]

    /// - Parameter directory: 缓存目录;默认 Application Support/VanessaNotch/lyrics。
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("VanessaNotch/lyrics", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// 读取:先内存,后磁盘;磁盘命中回填内存。未命中返回 nil。
    public func lyrics(forSongID id: Int64) -> Lyrics? {
        queue.sync {
            if let m = memory[id] { return m }
            let url = fileURL(id)
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(Lyrics.self, from: data) else { return nil }
            memory[id] = decoded
            return decoded
        }
    }

    /// 写入内存与磁盘。
    public func store(_ lyrics: Lyrics, forSongID id: Int64) {
        queue.sync {
            memory[id] = lyrics
            if let data = try? JSONEncoder().encode(lyrics) {
                try? data.write(to: fileURL(id), options: .atomic)
            }
        }
    }

    private func fileURL(_ id: Int64) -> URL {
        directory.appendingPathComponent("\(id).json")
    }
}
```

- [ ] **Step 5:运行测试确认通过**

Run: `swift test --filter LyricsCacheTests`
Expected: PASS(3 tests)。

- [ ] **Step 6:提交**

```bash
git add Sources/VanessaCore/Models/Lyrics.swift Sources/VanessaNetease/LyricsCache.swift Tests/VanessaNeteaseTests/LyricsCacheTests.swift
git commit -m "feat(netease): LyricsCache 内存+磁盘缓存;Lyrics 模型支持 Codable"
```

---

### Task 10:NeteaseLyricsRepository —— 编排选歌→歌词→缓存

**Files:**
- Create: `Sources/VanessaNetease/NeteaseLyricsRepository.swift`
- Test: `Tests/VanessaNeteaseTests/NeteaseLyricsRepositoryTests.swift`

- [ ] **Step 1:写失败测试(命中缓存不发网络 / 选中歌曲解析歌词 / 低置信度降级 / 缓存写入)**

`Tests/VanessaNeteaseTests/NeteaseLyricsRepositoryTests.swift`:
```swift
import XCTest
import VanessaCore
@testable import VanessaNetease

/// 假数据源:记录调用次数,返回预置数据。
private final class FakeSource: NeteaseDataSource, @unchecked Sendable {
    var candidates: [SongCandidate] = []
    var raw: [Int64: RawLyrics] = [:]
    private(set) var searchCalls = 0
    private(set) var lyricCalls = 0
    func search(title: String, artist: String) async throws -> [SongCandidate] { searchCalls += 1; return candidates }
    func fetchLyrics(songID: Int64) async throws -> RawLyrics { lyricCalls += 1; return raw[songID] ?? RawLyrics(lrc: nil, yrc: nil) }
}

final class NeteaseLyricsRepositoryTests: XCTestCase {
    private func tmpCache() -> LyricsCache {
        LyricsCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("repo-test-\(UUID().uuidString)"))
    }

    func test_matchedSong_returnsParsedLyricsAndCaches() async throws {
        let src = FakeSource()
        src.candidates = [SongCandidate(id: 111, title: "晴天", artists: ["周杰伦"], durationMs: 269000)]
        src.raw[111] = RawLyrics(lrc: "[00:01.00]行", yrc: nil)
        let cache = tmpCache()
        let repo = NeteaseLyricsRepository(source: src, cache: cache)
        let result = try await repo.lookup(title: "晴天", artist: "周杰伦", durationMs: 269000)
        guard case .matched(let id, let lyrics) = result else { return XCTFail("应为 matched") }
        XCTAssertEqual(id, 111)
        XCTAssertEqual(lyrics.lines.first?.text, "行")
        XCTAssertEqual(cache.lyrics(forSongID: 111)?.lines.first?.text, "行") // 已缓存
    }

    func test_cacheHit_skipsNetwork() async throws {
        let src = FakeSource()
        src.candidates = [SongCandidate(id: 111, title: "晴天", artists: ["周杰伦"], durationMs: 269000)]
        src.raw[111] = RawLyrics(lrc: "[00:01.00]行", yrc: nil)
        let cache = tmpCache()
        let repo = NeteaseLyricsRepository(source: src, cache: cache)
        _ = try await repo.lookup(title: "晴天", artist: "周杰伦", durationMs: 269000)
        let before = src.lyricCalls
        _ = try await repo.lookup(title: "晴天", artist: "周杰伦", durationMs: 269000)
        XCTAssertEqual(src.lyricCalls, before) // 第二次走缓存,未再拉歌词
    }

    func test_lowConfidence_returnsLowConfidence() async throws {
        let src = FakeSource()
        src.candidates = [SongCandidate(id: 999, title: "毫不相干XYZ", artists: ["别人"], durationMs: 999000)]
        let repo = NeteaseLyricsRepository(source: src, cache: tmpCache())
        let result = try await repo.lookup(title: "原曲ABC", artist: "原唱", durationMs: 100000)
        XCTAssertEqual(result, .lowConfidence)
        XCTAssertEqual(src.lyricCalls, 0) // 不拉歌词
    }

    func test_emptyCandidates_lowConfidence() async throws {
        let repo = NeteaseLyricsRepository(source: FakeSource(), cache: tmpCache())
        let result = try await repo.lookup(title: "x", artist: "y", durationMs: 1000)
        XCTAssertEqual(result, .lowConfidence)
    }
}
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter NeteaseLyricsRepositoryTests`
Expected: FAIL —「cannot find 'NeteaseDataSource' / 'NeteaseLyricsRepository'」。

- [ ] **Step 3:让 `NeteaseAPIClient` 符合数据源协议**

在 `Sources/VanessaNetease/NeteaseAPIClient.swift` 顶部(`NeteaseAPIError` 定义之后)新增协议,并让 client 遵循它。新增:
```swift
/// 数据源抽象:便于仓储注入假实现做单测。
public protocol NeteaseDataSource: Sendable {
    func search(title: String, artist: String) async throws -> [SongCandidate]
    func fetchLyrics(songID: Int64) async throws -> RawLyrics
}
```
并把 `public struct NeteaseAPIClient: Sendable {` 改为:
```swift
public struct NeteaseAPIClient: NeteaseDataSource, Sendable {
```

- [ ] **Step 4:实现 `NeteaseLyricsRepository`**

`Sources/VanessaNetease/NeteaseLyricsRepository.swift`:
```swift
import Foundation
import VanessaCore

/// 歌词查询结果。
public enum LyricsLookupResult: Equatable, Sendable {
    case matched(songID: Int64, lyrics: Lyrics)
    case lowConfidence   // 置信度不足:上层降级显示「歌名 - 歌手」
}

/// 仓储抽象,供 AppState 注入假实现测试。
public protocol LyricsRepository: Sendable {
    func lookup(title: String, artist: String, durationMs: Int) async throws -> LyricsLookupResult
}

/// 编排:搜索 → SongMatcher 选歌 → 拉歌词 → 解析 → 缓存。
public struct NeteaseLyricsRepository: LyricsRepository {
    private let source: NeteaseDataSource
    private let cache: LyricsCache

    public init(source: NeteaseDataSource, cache: LyricsCache = LyricsCache()) {
        self.source = source
        self.cache = cache
    }

    public func lookup(title: String, artist: String, durationMs: Int) async throws -> LyricsLookupResult {
        let candidates = try await source.search(title: title, artist: artist)
        let query = SongQuery(title: title, artist: artist, durationMs: durationMs)
        guard let best = SongMatcher.bestMatch(for: query, in: candidates) else {
            return .lowConfidence
        }
        if let cached = cache.lyrics(forSongID: best.id) {
            return .matched(songID: best.id, lyrics: cached)
        }
        let raw = try await source.fetchLyrics(songID: best.id)
        let lyrics = LyricsParser.parse(lrc: raw.lrc, yrc: raw.yrc)
        cache.store(lyrics, forSongID: best.id)
        return .matched(songID: best.id, lyrics: lyrics)
    }
}
```

- [ ] **Step 5:运行测试确认通过**

Run: `swift test --filter NeteaseLyricsRepositoryTests`
Expected: PASS(4 tests)。

- [ ] **Step 6:全量回归 + 提交**

Run: `swift test`
Expected: Core + Netease 全绿。
```bash
git add Sources/VanessaNetease Tests/VanessaNeteaseTests/NeteaseLyricsRepositoryTests.swift
git commit -m "feat(netease): NeteaseLyricsRepository 编排选歌/歌词/缓存,低置信度降级"
```

---

## Phase 3:正在播放数据源与编排(VanessaApp)

### Task 11:AdapterEventDecoder —— 解码 adapter 的一行 JSON

adapter(`mediaremote-adapter.pl ... stream`)按行输出 JSON,字段含:`bundleIdentifier`、`parentApplicationBundleIdentifier`、`playing`、`title`、`artist`、`album`、`duration`(秒)、`elapsedTime`(秒)、`timestamp`、`artworkData`(base64)、`playbackRate`。本任务把「一行 JSON + 采样时刻」解码成 `NowPlayingState?`,并按网易云 bundle id 过滤。**纯函数,可单测**;真正的进程读取在 Task 12(真机 QA)。

**Files:**
- Create: `Sources/VanessaApp/NowPlayingProvider.swift`(协议 + 解码器,替换 Phase 0 的 AppDelegate 占位无关,这是新文件)
- Test: `Tests/VanessaAppTests/AdapterEventDecoderTests.swift`

- [ ] **Step 1:写失败测试(网易云命中 / 非网易云过滤 / 暂停 / 字段缺失 / 坏 JSON)**

`Tests/VanessaAppTests/AdapterEventDecoderTests.swift`:
```swift
import XCTest
import VanessaCore
@testable import VanessaApp

final class AdapterEventDecoderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 5000)
    private let netease = "com.netease.163music"

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
        // 部分情况下网易云 bundle 在 parentApplicationBundleIdentifier
        let line = #"{"bundleIdentifier":"com.netease.helper","parentApplicationBundleIdentifier":"com.netease.163music","playing":true,"title":"a","artist":"b","duration":10,"elapsedTime":1}"#
        XCTAssertNotNil(AdapterEventDecoder.decode(line: line, sampledAt: now, neteaseBundleID: netease))
    }

    func test_missingOptionalFields_useDefaults() throws {
        let line = #"{"bundleIdentifier":"com.netease.163music","title":"纯音乐","duration":120,"elapsedTime":0}"#
        let s = try XCTUnwrap(AdapterEventDecoder.decode(line: line, sampledAt: now, neteaseBundleID: netease))
        XCTAssertEqual(s.artist, "")        // 缺失歌手 -> 空串
        XCTAssertFalse(s.isPlaying)         // 缺失 playing -> false
        XCTAssertEqual(s.rate, 1)           // 缺失 rate -> 1
    }

    func test_garbageLine_returnsNil() {
        XCTAssertNil(AdapterEventDecoder.decode(line: "not json", sampledAt: now, neteaseBundleID: netease))
        XCTAssertNil(AdapterEventDecoder.decode(line: "", sampledAt: now, neteaseBundleID: netease))
    }
}
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter AdapterEventDecoderTests`
Expected: FAIL —「cannot find 'AdapterEventDecoder'」。

- [ ] **Step 3:实现协议与解码器**

`Sources/VanessaApp/NowPlayingProvider.swift`:
```swift
import Foundation
import VanessaCore

/// 网易云 bundle id(以实际为准,可在设置中覆盖)。
public let neteaseBundleIDDefault = "com.netease.163music"

/// 正在播放数据源:吐 NowPlayingState 流;nil 表示空闲(无播放或来源非网易云)。
public protocol NowPlayingProvider: AnyObject {
    /// 状态流。nil = 空闲。
    var states: AsyncStream<NowPlayingState?> { get }
    func start()
    func stop()
}

/// 把 adapter 的一行 JSON 解码成 NowPlayingState(纯函数)。
public enum AdapterEventDecoder {
    /// - Parameters:
    ///   - line: adapter stream 的一行 JSON。
    ///   - sampledAt: 收到该行的时刻(作为采样时刻)。
    ///   - neteaseBundleID: 网易云 bundle id;来源非网易云返回 nil。
    /// - Returns: 解码后的状态;非网易云/坏数据返回 nil。
    public static func decode(line: String, sampledAt: Date, neteaseBundleID: String) -> NowPlayingState? {
        guard let data = line.data(using: .utf8), !data.isEmpty,
              let event = try? JSONDecoder().decode(AdapterEvent.self, from: data) else { return nil }
        let isNetease = event.bundleIdentifier == neteaseBundleID
            || event.parentApplicationBundleIdentifier == neteaseBundleID
        guard isNetease else { return nil }
        return NowPlayingState(
            title: event.title ?? "",
            artist: event.artist ?? "",
            album: event.album ?? "",
            artworkData: event.artworkData.flatMap { Data(base64Encoded: $0) },
            duration: event.duration ?? 0,
            elapsed: event.elapsedTime ?? 0,
            sampledAt: sampledAt,
            rate: event.playbackRate ?? 1,
            isPlaying: event.playing ?? false,
            sourceBundleID: event.bundleIdentifier ?? neteaseBundleID
        )
    }

    /// adapter JSON 结构(仅取需要字段,全可选以容忍缺失)。
    struct AdapterEvent: Decodable {
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let playing: Bool?
        let title: String?
        let artist: String?
        let album: String?
        let duration: TimeInterval?
        let elapsedTime: TimeInterval?
        let playbackRate: Double?
        let artworkData: String?
    }
}
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter AdapterEventDecoderTests`
Expected: PASS(5 tests)。

- [ ] **Step 5:提交**

```bash
git add Sources/VanessaApp/NowPlayingProvider.swift Tests/VanessaAppTests/AdapterEventDecoderTests.swift
git commit -m "feat(app): NowPlayingProvider 协议 + AdapterEventDecoder 纯解码与网易云过滤"
```

---

### Task 12:MediaRemoteNowPlayingProvider —— 进程化 adapter

> 该类负责 spawn `perl mediaremote-adapter.pl <framework> stream`、逐行读 stdout、用 `AdapterEventDecoder` 解码、把状态推进 `AsyncStream`;进程退出/无法启动时推 `nil` 并标记不可用。进程交互无法稳定单测,**靠 Phase 6 真机 QA 验证**;此处只保证可编译、接口清晰、解码复用 Task 11。

**Files:**
- Create: `Sources/VanessaApp/MediaRemoteNowPlayingProvider.swift`

- [ ] **Step 1:实现 provider(无单测,编译验证)**

`Sources/VanessaApp/MediaRemoteNowPlayingProvider.swift`:
```swift
import Foundation
import VanessaCore

/// 经 ungive/mediaremote-adapter 读取系统 NowPlaying。
/// 通过 Process 运行 perl 脚本 + 私有 framework,逐行解码 JSON。
public final class MediaRemoteNowPlayingProvider: NowPlayingProvider, @unchecked Sendable {
    public let states: AsyncStream<NowPlayingState?>
    private let continuation: AsyncStream<NowPlayingState?>.Continuation
    private let perlPath: String
    private let scriptPath: String
    private let frameworkPath: String
    private let neteaseBundleID: String
    private var process: Process?
    private var buffer = Data()

    /// adapter 是否可用(脚本/framework 是否就绪)。供 UI 显示「警告态」。
    public private(set) var isAvailable: Bool = true

    /// - Parameters:
    ///   - scriptPath: 内嵌的 mediaremote-adapter.pl 绝对路径。
    ///   - frameworkPath: 内嵌的 MediaRemoteAdapter.framework 绝对路径。
    public init(scriptPath: String, frameworkPath: String,
                perlPath: String = "/usr/bin/perl",
                neteaseBundleID: String = neteaseBundleIDDefault) {
        self.perlPath = perlPath
        self.scriptPath = scriptPath
        self.frameworkPath = frameworkPath
        self.neteaseBundleID = neteaseBundleID
        var cont: AsyncStream<NowPlayingState?>.Continuation!
        self.states = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    public func start() {
        // 资源缺失:标记不可用并发出空闲态
        guard FileManager.default.fileExists(atPath: scriptPath),
              FileManager.default.fileExists(atPath: frameworkPath) else {
            isAvailable = false
            continuation.yield(nil)
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: perlPath)
        proc.arguments = [scriptPath, frameworkPath, "stream"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        proc.terminationHandler = { [weak self] _ in
            self?.isAvailable = false
            self?.continuation.yield(nil)
        }
        do {
            try proc.run()
            self.process = proc
            self.isAvailable = true
        } catch {
            isAvailable = false
            continuation.yield(nil)
        }
    }

    public func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        continuation.finish()
    }

    /// 累积字节,按换行切分逐行解码。
    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        let newline = UInt8(ascii: "\n")
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            let state = AdapterEventDecoder.decode(line: line, sampledAt: Date(), neteaseBundleID: neteaseBundleID)
            continuation.yield(state)
        }
    }
}
```

- [ ] **Step 2:编译验证**

Run: `swift build`
Expected: 编译通过(无测试断言;此类由 Phase 6 真机 QA 覆盖)。

- [ ] **Step 3:提交**

```bash
git add Sources/VanessaApp/MediaRemoteNowPlayingProvider.swift
git commit -m "feat(app): MediaRemoteNowPlayingProvider 进程化 adapter,逐行解码"
```

---

### Task 13:AppState —— 编排所有模块,输出 UI 状态

**Files:**
- Create: `Sources/VanessaApp/AppState.swift`(替换 Phase 0 的 AppDelegate 占位文件内容请保留 `VanessaApp.bootstrapped`,本任务新建独立文件)
- Test: `Tests/VanessaAppTests/AppStateTests.swift`

- [ ] **Step 1:写失败测试(空闲 / 换歌拉到歌词进入播放 / 低置信度降级文案 / 纯音乐占位 / adapter 不可用警告)**

`Tests/VanessaAppTests/AppStateTests.swift`:
```swift
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
        XCTAssertEqual(d.lineText, "我爱你") // elapsed=1s,位置落在第 0 行
    }

    func test_lowConfidence_showsTitleArtistFallback() async {
        let p = FakeProvider()
        let state = AppState(provider: p, repository: FakeRepo(result: .lowConfidence))
        state.start()
        p.emit(playing("某歌", "某人"))
        await state.drainForTesting()
        guard case .playing(let d) = state.ui else { return XCTFail("应进入 playing") }
        XCTAssertEqual(d.lineText, "某歌 - 某人") // 降级文案
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
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter AppStateTests`
Expected: FAIL —「cannot find 'AppState' / 'AppUIState' / 'PlayingDisplay'」。

- [ ] **Step 3:实现 `AppState` 与 UI 状态模型**

`Sources/VanessaApp/AppState.swift`:
```swift
import Foundation
import SwiftUI
import VanessaCore
import VanessaNetease

/// 面板展示数据。
public struct PlayingDisplay: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var artworkData: Data?
    public var lineText: String          // 当前行 / 「♪ 纯音乐」 / 「歌名 - 歌手」
    public var words: [Word]             // 逐字(空表示整行高亮)
    public var position: LyricPosition
    public var isPlaying: Bool
}

/// 全局 UI 状态。
public enum AppUIState: Equatable, Sendable {
    case idle
    case warning(message: String)
    case playing(PlayingDisplay)
}

/// 编排:订阅 provider → 换歌拉歌词 → 30fps tick 算高亮 → 输出 AppUIState。
@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var ui: AppUIState = .idle

    private let provider: NowPlayingProvider
    private let repository: LyricsRepository
    private let neteaseBundleID: String

    private var currentIdentity: String?
    private var currentLyrics: Lyrics = Lyrics(lines: [])
    private var fallbackText: String?      // 非 nil 时表示降级显示该文案
    private var clock: PlaybackClock?
    private var latestState: NowPlayingState?
    private var streamTask: Task<Void, Never>?
    private var ticker: Timer?

    public init(provider: NowPlayingProvider, repository: LyricsRepository,
                neteaseBundleID: String = neteaseBundleIDDefault) {
        self.provider = provider
        self.repository = repository
        self.neteaseBundleID = neteaseBundleID
    }

    /// 启动:订阅状态流并开 30fps tick。
    public func start() {
        provider.start()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.provider.states {
                await self.handle(state)
            }
        }
        startTicker()
    }

    public func stop() {
        streamTask?.cancel(); streamTask = nil
        ticker?.invalidate(); ticker = nil
        provider.stop()
    }

    /// 处理一次来源状态。nil=空闲;换歌则异步拉歌词。
    func handle(_ state: NowPlayingState?) async {
        guard let state else {
            currentIdentity = nil; latestState = nil; clock = nil
            ui = .idle
            return
        }
        latestState = state
        clock = PlaybackClock(state: state)
        if state.songIdentity != currentIdentity {
            currentIdentity = state.songIdentity
            await loadLyrics(for: state)
        }
        refresh()
    }

    /// 拉歌词:成功填充 lyrics;低置信度/失败则降级为「歌名 - 歌手」。
    private func loadLyrics(for state: NowPlayingState) async {
        do {
            let result = try await repository.lookup(title: state.title, artist: state.artist,
                                                     durationMs: Int(state.duration * 1000))
            switch result {
            case .matched(_, let lyrics):
                currentLyrics = lyrics
                fallbackText = lyrics.isEmpty ? "♪ 纯音乐" : nil
            case .lowConfidence:
                currentLyrics = Lyrics(lines: [])
                fallbackText = "\(state.title) - \(state.artist)"
            }
        } catch {
            currentLyrics = Lyrics(lines: [])
            fallbackText = "\(state.title) - \(state.artist)"
        }
    }

    /// 30fps 推进。
    private func startTicker() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// 由当前 clock + 歌词重算 UI。
    func refresh() {
        guard let state = latestState, let clock else { return }
        let posMs = clock.positionMs(at: Date())
        let position = LyricSyncEngine.locate(positionMs: posMs, in: currentLyrics)
        let lineText: String
        let words: [Word]
        if let fb = fallbackText {
            lineText = fb; words = []
        } else if let idx = position.lineIndex, idx < currentLyrics.lines.count {
            lineText = currentLyrics.lines[idx].text
            words = currentLyrics.lines[idx].words
        } else {
            // 首行之前:显示首行文本(静态),无高亮
            lineText = currentLyrics.lines.first?.text ?? "\(state.title) - \(state.artist)"
            words = []
        }
        ui = .playing(PlayingDisplay(title: state.title, artist: state.artist,
                                     artworkData: state.artworkData, lineText: lineText,
                                     words: words, position: position, isPlaying: state.isPlaying))
    }

    /// 标记 adapter 不可用,进入警告态(供 main 在 provider 不可用时调用)。
    public func markUnavailable(message: String) { ui = .warning(message: message) }

    /// 测试辅助:让出当前任务,等待已投喂的状态被异步消费完。
    public func drainForTesting() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter AppStateTests`
Expected: PASS(5 tests)。若 `drainForTesting` 偶发不稳,可适当加长 sleep。

- [ ] **Step 5:全量回归 + 提交**

Run: `swift test`
Expected: 三个测试 target 全绿。
```bash
git add Sources/VanessaApp/AppState.swift Tests/VanessaAppTests/AppStateTests.swift
git commit -m "feat(app): AppState 编排来源/歌词/时钟,输出 idle/warning/playing"
```

---

## Phase 4:刘海窗口(VanessaApp)

### Task 14:NotchGeometry —— 屏幕几何推算窗口位置(纯函数)

> 把「屏幕 frame + 刘海尺寸 + 面板尺寸」算成窗口 frame 是纯函数,可单测。`NSScreen` 读取真实刘海留到 Task 15。坐标系:AppKit 全局坐标(原点左下),窗口贴屏幕顶部、水平居中于刘海。

**Files:**
- Create: `Sources/VanessaApp/NotchGeometry.swift`
- Test: `Tests/VanessaAppTests/NotchGeometryTests.swift`

- [ ] **Step 1:写失败测试(有刘海居中贴顶 / 无刘海降级顶部居中 / 面板宽度)**

`Tests/VanessaAppTests/NotchGeometryTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import VanessaApp

final class NotchGeometryTests: XCTestCase {
    // 屏幕:1512x982,原点(0,0)。
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func test_withNotch_panelHangsBelowNotchCentered() {
        let notch = CGSize(width: 170, height: 34)
        let panel = CGSize(width: 230, height: 60)
        let frame = NotchGeometry.panelFrame(screenFrame: screen, notchSize: notch, panelSize: panel)
        // 水平居中
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        // 顶部对齐:面板顶 = 屏幕顶(刘海下沿),即 y = 屏幕高 - 刘海高 - 面板高
        XCTAssertEqual(frame.origin.y, screen.height - notch.height - panel.height, accuracy: 0.5)
        XCTAssertEqual(frame.width, panel.width, accuracy: 0.5)
    }

    func test_withoutNotch_fallsBackToTopCentered() {
        let panel = CGSize(width: 230, height: 60)
        // notchSize 为 .zero 表示无刘海屏,降级:贴屏幕顶居中
        let frame = NotchGeometry.panelFrame(screenFrame: screen, notchSize: .zero, panelSize: panel)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, screen.height - panel.height, accuracy: 0.5)
    }

    func test_pillFrame_centeredAtNotch() {
        let notch = CGSize(width: 170, height: 34)
        let pill = CGSize(width: 90, height: 28)
        let frame = NotchGeometry.pillFrame(screenFrame: screen, notchSize: notch, pillSize: pill)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, screen.height - notch.height - pill.height, accuracy: 0.5)
    }
}
```

- [ ] **Step 2:运行测试确认失败**

Run: `swift test --filter NotchGeometryTests`
Expected: FAIL —「cannot find 'NotchGeometry'」。

- [ ] **Step 3:实现 `NotchGeometry`**

`Sources/VanessaApp/NotchGeometry.swift`:
```swift
import CoreGraphics

/// 纯函数:由屏幕与刘海尺寸推算置顶窗口的全局 frame(AppKit 坐标,原点左下)。
public enum NotchGeometry {
    /// 播放面板 frame:水平居中于屏幕、紧贴刘海下沿向下展开。
    /// notchSize 为 .zero(无刘海)时降级为紧贴屏幕顶部居中。
    public static func panelFrame(screenFrame: CGRect, notchSize: CGSize, panelSize: CGSize) -> CGRect {
        hang(screenFrame: screenFrame, topInset: notchSize.height, size: panelSize)
    }

    /// 空闲胶囊 frame:同样贴刘海下沿居中。
    public static func pillFrame(screenFrame: CGRect, notchSize: CGSize, pillSize: CGSize) -> CGRect {
        hang(screenFrame: screenFrame, topInset: notchSize.height, size: pillSize)
    }

    /// 通用:在屏幕顶部下方 topInset 处、水平居中放置 size 大小的窗口。
    private static func hang(screenFrame: CGRect, topInset: CGFloat, size: CGSize) -> CGRect {
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - topInset - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
```

- [ ] **Step 4:运行测试确认通过**

Run: `swift test --filter NotchGeometryTests`
Expected: PASS(3 tests)。

- [ ] **Step 5:提交**

```bash
git add Sources/VanessaApp/NotchGeometry.swift Tests/VanessaAppTests/NotchGeometryTests.swift
git commit -m "feat(app): NotchGeometry 纯函数推算面板/胶囊窗口位置,无刘海降级"
```

---

### Task 15:NotchWindowController —— 置顶透明窗口与多屏定位

> 创建 borderless、透明、`.statusBar` 以上层级、忽略鼠标穿透可配的 NSWindow,托管一个 SwiftUI 根视图;读取主屏刘海尺寸(`safeAreaInsets.top` / `auxiliaryTopLeftArea`),用 `NotchGeometry` 定位;监听屏幕变化重定位。GUI 行为靠真机 QA;此处保证可编译、定位逻辑复用 Task 14。

**Files:**
- Create: `Sources/VanessaApp/NotchWindowController.swift`

- [ ] **Step 1:实现窗口控制器(无单测,编译验证)**

`Sources/VanessaApp/NotchWindowController.swift`:
```swift
import AppKit
import SwiftUI
import CoreGraphics

/// 管理刘海处的置顶透明窗口:创建、定位、随屏幕变化重定位。
@MainActor
public final class NotchWindowController {
    private let window: NSWindow
    private let hosting: NSHostingView<AnyView>
    /// 当前内容期望尺寸(由调用方根据 idle/playing 设定)。
    public var contentSize: CGSize = CGSize(width: 230, height: 64) { didSet { reposition() } }

    /// - Parameter rootView: SwiftUI 根视图(随 AppState 变化)。
    public init(rootView: AnyView) {
        hosting = NSHostingView(rootView: rootView)
        window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar + 1            // 盖在菜单栏/刘海层之上
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false        // 胶囊需要可点击
        window.contentView = hosting
        reposition()
    }

    public func show() { window.orderFrontRegardless(); reposition() }
    public func hide() { window.orderOut(nil) }

    /// 替换根视图(状态切换时调用)。
    public func update(rootView: AnyView) { hosting.rootView = rootView }

    /// 重新定位到主屏刘海下方。
    public func reposition() {
        guard let screen = NSScreen.main else { return }
        let notch = Self.notchSize(of: screen)
        let frame = NotchGeometry.panelFrame(screenFrame: screen.frame,
                                             notchSize: notch, panelSize: contentSize)
        window.setFrame(frame, display: true)
    }

    /// 读取屏幕刘海尺寸;无刘海返回 .zero(交由 NotchGeometry 降级)。
    static func notchSize(of screen: NSScreen) -> CGSize {
        // 有刘海机型:safeAreaInsets.top > 0;刘海宽用 auxiliaryTopLeftArea 推算。
        let top = screen.safeAreaInsets.top
        guard top > 0 else { return .zero }
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth = max(0, screen.frame.width - leftWidth - rightWidth)
        return CGSize(width: notchWidth > 0 ? notchWidth : 200, height: top)
    }

    /// 注册屏幕参数变化通知,变化时重定位。
    public func observeScreenChanges() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }
}
```

- [ ] **Step 2:编译验证**

Run: `swift build`
Expected: 编译通过。

- [ ] **Step 3:提交**

```bash
git add Sources/VanessaApp/NotchWindowController.swift
git commit -m "feat(app): NotchWindowController 置顶透明窗口+刘海定位+屏幕变化重定位"
```

---

## Phase 5:SwiftUI 视图与 App 装配(VanessaApp + vanessa-notch)

> 视图为纯展示,绑定 `AppState.ui`。视觉细节(逐字高亮渐变、装饰音频条动画)以真机/截图 QA 为准;此处给出完整可编译实现,断言性测试不适用。

### Task 16:逐字卡拉OK文本视图

**Files:**
- Create: `Sources/VanessaApp/Views/KaraokeLineView.swift`

- [ ] **Step 1:实现逐字高亮行视图**

`Sources/VanessaApp/Views/KaraokeLineView.swift`:
```swift
import SwiftUI
import VanessaCore

/// 单行逐字高亮:已唱部分亮白,未唱部分半透明;用渐变遮罩按进度推进。
struct KaraokeLineView: View {
    let text: String
    let words: [Word]
    let position: LyricPosition
    var fontSize: CGFloat = 13

    var body: some View {
        ZStack {
            base.foregroundStyle(.white.opacity(0.45))         // 底层:未唱
            base.foregroundStyle(.white)                        // 顶层:已唱(被遮罩裁切)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: geo.size.width * CGFloat(progress))
                    }
                }
        }
        .animation(.linear(duration: 0.1), value: progress)
    }

    private var base: some View {
        Text(text).font(.system(size: fontSize, weight: .semibold)).lineLimit(1)
    }

    /// 整行已唱比例 0...1。有逐字用「已完成字 + 当前字进度」,无逐字用 lineProgress。
    private var progress: Double {
        guard !words.isEmpty, let active = position.activeWordIndex else {
            return position.lineProgress
        }
        let total = max(words.count, 1)
        return (Double(active) + position.wordProgress) / Double(total)
    }
}
```

- [ ] **Step 2:编译验证**

Run: `swift build`
Expected: 编译通过。

- [ ] **Step 3:提交**

```bash
git add Sources/VanessaApp/Views/KaraokeLineView.swift
git commit -m "feat(app): KaraokeLineView 逐字渐进高亮"
```

---

### Task 17:播放面板 / 空闲胶囊 / 设置视图

**Files:**
- Create: `Sources/VanessaApp/Views/PlayingPanelView.swift`
- Create: `Sources/VanessaApp/Views/IdlePillView.swift`
- Create: `Sources/VanessaApp/Views/SettingsView.swift`
- Create: `Sources/VanessaApp/Settings.swift`

- [ ] **Step 1:实现设置模型**

`Sources/VanessaApp/Settings.swift`:
```swift
import Foundation
import SwiftUI

/// 用户设置,持久化到 UserDefaults。
@MainActor
public final class Settings: ObservableObject {
    @AppStorage("lyricFontSize") public var fontSize: Double = 13
    @AppStorage("offsetX") public var offsetX: Double = 0   // 位置水平微调(像素)
    @AppStorage("launchAtLogin") public var launchAtLogin: Bool = false
    public init() {}
}
```

- [ ] **Step 2:实现装饰音频条**

`Sources/VanessaApp/Views/IdlePillView.swift`:
```swift
import SwiftUI

/// 装饰性音频跳动条(非真实频谱;仅按 isPlaying 决定是否跳动)。
struct DecorativeBars: View {
    let isPlaying: Bool
    @State private var phase: Double = 0
    private let count = 4

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(Color(red: 1, green: 0.37, blue: 0.43))
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .frame(height: 18, alignment: .bottom)
        .onAppear { animate() }
        .onChange(of: isPlaying) { _, _ in animate() }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard isPlaying else { return 4 }
        let base = sin(phase + Double(i) * 1.1)
        return 6 + CGFloat(abs(base)) * 12
    }

    private func animate() {
        guard isPlaying else { return }
        withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
            phase = .pi
        }
    }
}

/// 空闲胶囊:点击打开设置。
struct IdlePillView: View {
    let isWarning: Bool
    var onTap: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "music.note")
                .font(.system(size: 11))
                .foregroundStyle(isWarning ? .yellow : .white.opacity(0.8))
        }
        .padding(.horizontal, 12).frame(height: 22)
        .background(Capsule().fill(.black.opacity(0.82)))
        .contentShape(Capsule())
        .onTapGesture { onTap() }
    }
}
```

- [ ] **Step 3:实现播放面板**

`Sources/VanessaApp/Views/PlayingPanelView.swift`:
```swift
import SwiftUI
import VanessaCore

/// 播放面板:左封面 + 右装饰条 + 下方单行逐字歌词。
struct PlayingPanelView: View {
    let display: PlayingDisplay
    var fontSize: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                cover
                DecorativeBars(isPlaying: display.isPlaying)
                Spacer(minLength: 0)
            }
            KaraokeLineView(text: display.lineText, words: display.words,
                            position: display.position, fontSize: fontSize)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.82)))
    }

    @ViewBuilder private var cover: some View {
        if let data = display.artworkData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
        }
    }
}
```

- [ ] **Step 4:实现设置视图**

`Sources/VanessaApp/Views/SettingsView.swift`:
```swift
import SwiftUI

/// 设置弹窗:字号、位置微调、开机启动、状态说明、退出。
struct SettingsView: View {
    @ObservedObject var settings: Settings
    let adapterAvailable: Bool
    var onQuit: () -> Void

    var body: some View {
        Form {
            if !adapterAvailable {
                Section("状态") {
                    Label("无法读取系统正在播放信息。请确认已授权,或重启 App 重试。",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            Section("歌词") {
                Slider(value: $settings.fontSize, in: 10...20, step: 1) { Text("字号") }
                Slider(value: $settings.offsetX, in: -200...200, step: 1) { Text("水平微调") }
            }
            Section("通用") {
                Toggle("开机启动", isOn: $settings.launchAtLogin)
                Button("退出 Vanessa-Notch", role: .destructive, action: onQuit)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 280)
    }
}
```

- [ ] **Step 5:编译验证**

Run: `swift build`
Expected: 编译通过。

- [ ] **Step 6:提交**

```bash
git add Sources/VanessaApp/Settings.swift Sources/VanessaApp/Views
git commit -m "feat(app): 播放面板/空闲胶囊/设置视图/装饰音频条/设置模型"
```

---

### Task 18:AppDelegate —— 装配状态项、窗口、AppState

**Files:**
- Modify: `Sources/VanessaApp/AppDelegate.swift`(替换 Phase 0 占位)

- [ ] **Step 1:实现 AppDelegate**

把 `Sources/VanessaApp/AppDelegate.swift` 全部替换为:
```swift
import AppKit
import SwiftUI
import Combine
import VanessaCore
import VanessaNetease

/// App 装配:无 Dock 图标的菜单栏代理。创建 provider/repository/AppState,
/// 把刘海窗口内容随 AppState.ui 切换;空闲胶囊点击弹设置。
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var windowController: NotchWindowController!
    private var settings = Settings()
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var adapterAvailable = true

    /// 内嵌资源路径:bundle 内 Resources 下的 adapter 脚本与 framework。
    private func adapterPaths() -> (script: String, framework: String) {
        let res = Bundle.main.resourcePath ?? ""
        return (res + "/mediaremote-adapter.pl", res + "/MediaRemoteAdapter.framework")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = adapterPaths()
        let provider = MediaRemoteNowPlayingProvider(scriptPath: paths.script, frameworkPath: paths.framework)
        let cache = LyricsCache()
        let repository = NeteaseLyricsRepository(source: NeteaseAPIClient(), cache: cache)
        appState = AppState(provider: provider, repository: repository)

        windowController = NotchWindowController(rootView: AnyView(EmptyView()))
        windowController.observeScreenChanges()
        windowController.show()

        // 状态栏图标(右上角菜单栏),点击弹设置
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Vanessa-Notch")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openSettings)

        // 订阅 UI 状态,刷新窗口内容与尺寸
        cancellable = appState.$ui.sink { [weak self] ui in
            self?.render(ui)
        }
        appState.start()
    }

    /// 根据 UI 状态渲染窗口内容并调整尺寸。
    private func render(_ ui: AppUIState) {
        switch ui {
        case .idle:
            windowController.contentSize = CGSize(width: 90, height: 28)
            windowController.update(rootView: AnyView(IdlePillView(isWarning: false) { [weak self] in self?.openSettings() }))
        case .warning(let message):
            adapterAvailable = false
            _ = message
            windowController.contentSize = CGSize(width: 90, height: 28)
            windowController.update(rootView: AnyView(IdlePillView(isWarning: true) { [weak self] in self?.openSettings() }))
        case .playing(let d):
            windowController.contentSize = CGSize(width: 230, height: 64)
            windowController.update(rootView: AnyView(
                PlayingPanelView(display: d, fontSize: CGFloat(settings.fontSize))
            ))
        }
    }

    /// 打开设置弹窗(独立普通窗口)。
    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, adapterAvailable: adapterAvailable) {
                NSApp.terminate(nil)
            }
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.title = "Vanessa-Notch 设置"
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
```

注意:删除 Phase 0 占位里的 `public enum VanessaApp { ... }`(已不再需要;若 `vanessa-notch/main.swift` 仍引用它,会在 Task 19 一并改掉)。

- [ ] **Step 2:编译验证**

Run: `swift build`
Expected: 编译通过(`main.swift` 仍引用 `VanessaApp.bootstrapped` 会报错——下个任务修复)。若仅此一处报错属预期,继续 Task 19。

- [ ] **Step 3:提交(暂不要求 build 全绿,下任务补 main)**

```bash
git add Sources/VanessaApp/AppDelegate.swift
git commit -m "feat(app): AppDelegate 装配状态项/刘海窗口/设置弹窗,订阅 AppState"
```

---

### Task 19:启动入口 main.swift

**Files:**
- Modify: `Sources/vanessa-notch/main.swift`(替换 Phase 0 占位)

- [ ] **Step 1:替换启动入口**

`Sources/vanessa-notch/main.swift`:
```swift
import AppKit
import VanessaApp

// 菜单栏代理:无 Dock 图标(.accessory)。LSUIElement 由打包脚本写入 Info.plist。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2:编译并整体回归**

Run: `swift build && swift test`
Expected: `swift build` 成功;`swift test` 全部 target 绿。

- [ ] **Step 3:提交**

```bash
git add Sources/vanessa-notch/main.swift
git commit -m "feat(app): 启动入口 main.swift 装配 NSApplication(accessory 模式)"
```

---

## Phase 6:打包成 .app 与分发

### Task 20:Info.plist 模板与 .app 组装脚本

> SwiftPM 产出的是裸可执行文件;本任务用脚本把它装进 `Vanessa-Notch.app` bundle,写入 `LSUIElement=YES`(无 Dock 图标),并把 adapter 的 `mediaremote-adapter.pl` 与 `MediaRemoteAdapter.framework` 拷进 `Contents/Resources/`(`AppDelegate.adapterPaths()` 按此路径查找)。

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `vendor/README.md`(说明如何放置 adapter 产物)

- [ ] **Step 1:写 Info.plist 模板**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Vanessa-Notch</string>
    <key>CFBundleDisplayName</key><string>Vanessa-Notch</string>
    <key>CFBundleIdentifier</key><string>com.vanessa.notch</string>
    <key>CFBundleVersion</key><string>0.0.1</string>
    <key>CFBundleShortVersionString</key><string>0.0.1</string>
    <key>CFBundleExecutable</key><string>vanessa-notch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

- [ ] **Step 2:写 vendor 说明(adapter 产物来源)**

`vendor/README.md`:
```markdown
# 第三方 adapter 产物放置说明

从 https://github.com/ungive/mediaremote-adapter 获取以下两项,放到本目录:

- `vendor/mediaremote-adapter.pl`            （perl 流式脚本）
- `vendor/MediaRemoteAdapter.framework`      （私有 framework,**不链接**,仅运行时由 perl 加载）

打包脚本 `Scripts/build-app.sh` 会把它们拷进 `Vanessa-Notch.app/Contents/Resources/`。
注意:必须传绝对路径给 perl 脚本(已在 AppDelegate.adapterPaths() 处理)。
缺失时 App 不崩溃,仅显示「警告态」空闲胶囊。
```

- [ ] **Step 3:写组装脚本**

`Scripts/build-app.sh`:
```bash
#!/usr/bin/env bash
# 组装 Vanessa-Notch.app:编译 release -> 拼 bundle -> 写 Info.plist -> 拷 adapter 资源。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Vanessa-Notch.app"
BIN_NAME="vanessa-notch"

echo "==> 编译 release"
swift build -c release --product "$BIN_NAME"
BIN_PATH="$(swift build -c release --product "$BIN_NAME" --show-bin-path)/$BIN_NAME"

echo "==> 重建 bundle 目录"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 拷可执行文件与 Info.plist"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> 拷 adapter 资源(若存在)"
if [ -f "$ROOT/vendor/mediaremote-adapter.pl" ]; then
  cp "$ROOT/vendor/mediaremote-adapter.pl" "$APP/Contents/Resources/"
else
  echo "   [警告] 未找到 vendor/mediaremote-adapter.pl —— App 将以警告态运行"
fi
if [ -d "$ROOT/vendor/MediaRemoteAdapter.framework" ]; then
  cp -R "$ROOT/vendor/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"
else
  echo "   [警告] 未找到 vendor/MediaRemoteAdapter.framework —— App 将以警告态运行"
fi

echo "==> 完成:$APP"
```

- [ ] **Step 4:赋可执行权限并组装**

Run:
```bash
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh
```
Expected: 生成 `dist/Vanessa-Notch.app`;若 vendor 缺失会打印警告但仍生成 bundle。

- [ ] **Step 5:启动冒烟(手动验证,无 Dock 图标 + 菜单栏图标出现)**

Run: `open dist/Vanessa-Notch.app`
Expected: 无 Dock 图标;右上角菜单栏出现 ♪ 图标;无网易云播放时刘海处显示空闲胶囊(或警告态)。点击菜单栏图标弹出设置窗口。
> 这是真机 QA 步骤;若 adapter 资源缺失,胶囊应为黄色警告态,设置内显示状态说明,且 App 不崩溃。

- [ ] **Step 6:提交**

```bash
printf '\ndist/\nvendor/mediaremote-adapter.pl\nvendor/MediaRemoteAdapter.framework\n' >> .gitignore
git add Resources/Info.plist Scripts/build-app.sh vendor/README.md .gitignore
git commit -m "build: .app 组装脚本 + Info.plist(LSUIElement) + adapter 资源说明"
```

---

### Task 21:notarization 与分发说明(文档,无代码)

**Files:**
- Create: `docs/DISTRIBUTION.md`

- [ ] **Step 1:写分发说明**

`docs/DISTRIBUTION.md`:
```markdown
# 分发说明

本 App 因使用网易云非公开接口 + 私有 MediaRemote,**无法上架 App Store**。分发方式:notarized DMG 直接下载,定位个人/开源使用。

## 步骤(需 Apple Developer 账号)
1. `./Scripts/build-app.sh` 生成 `dist/Vanessa-Notch.app`。
2. 代码签名(Developer ID Application 证书):
   `codesign --deep --force --options runtime --sign "Developer ID Application: <你的名字>" dist/Vanessa-Notch.app`
3. 打包 DMG:`hdiutil create -volname Vanessa-Notch -srcfolder dist/Vanessa-Notch.app -ov -format UDZO dist/Vanessa-Notch.dmg`
4. 公证:`xcrun notarytool submit dist/Vanessa-Notch.dmg --keychain-profile <profile> --wait`
5. 装订:`xcrun stapler staple dist/Vanessa-Notch.dmg`

> 私有 framework 由 perl 运行时加载、不参与链接,通常不影响 Developer ID 签名;若 hardened runtime 拦截,记录日志按警告态降级,不崩溃。
```

- [ ] **Step 2:提交**

```bash
git add docs/DISTRIBUTION.md
git commit -m "docs: notarized DMG 分发说明"
```

---

## 真机 QA 清单(无法自动化部分,执行完成后逐项确认)

设计文档第 9/6/8 节要求的人工验证项:
- [ ] 换歌:网易云切歌后,面板标题/封面/歌词随之更新。
- [ ] 拖动进度:网易云内拖动进度条,逐字高亮位置同步跳转。
- [ ] 暂停:面板保留,歌词与装饰音频条静止。
- [ ] 纯音乐/无歌词:歌词行显示「♪ 纯音乐」。
- [ ] 低置信度:对冷门/错搜歌曲,显示「歌名 - 歌手」而非错歌词。
- [ ] 断网:显示「歌名 - 歌手」;恢复网络后切歌可重新拉到歌词。
- [ ] 空闲:非网易云来源(如 Apple Music)或无播放时,收成空闲胶囊。
- [ ] adapter 不可用:vendor 资源缺失或被系统拦时,显示黄色警告胶囊 + 设置内状态说明,App 不崩溃。
- [ ] 外接非刘海屏:降级为顶部居中浮动圆角面板(NotchGeometry 的 .zero 分支)。
- [ ] 多屏 / 屏幕热插拔:`didChangeScreenParameters` 后窗口重定位到主屏刘海。
- [ ] macOS 15.4+ 实测:adapter 在 entitlement 限制下仍能读取 NowPlaying。

---

## 自检结果(Self-Review)

**1. Spec 覆盖核对(逐节对照设计文档):**
- §2 技术选型(SwiftUI+AppKit、菜单栏代理、adapter)→ Task 18/19/20、Task 12。
- §3.1 NowPlaying 字段与网易云过滤 → Task 11(AdapterEventDecoder)、Task 12。
- §3.2 歌词流程(搜索→选歌→歌词→缓存、低置信度降级)→ Task 8/9/10。
- §3.3 进度同步(elapsed+漂移、30fps tick)→ Task 6(PlaybackClock)、Task 13(ticker)。
- §4 模块拆分 → 全部模块各有对应 Task,类型/方法名跨任务一致(见下)。
- §4 数据模型 → Task 1。
- §5 数据流 → Task 13(AppState 编排)串起全链路。
- §6 运行状态(播放面板/暂停/空闲胶囊/纯音乐占位/警告态)→ Task 13/17/18。
- §7 装饰音频条非真实频谱、不上架 → Task 17(DecorativeBars 注释)、Task 21。
- §8 错误处理(adapter 不可用/接口失败降级/低置信度/断网/无刘海降级)→ Task 12/10/13/14。
- §9 测试策略(四个纯函数单测、APIClient 打桩、AppState 假 provider)→ Task 2–6/8/13。
- §11 YAGNI(不做播放控制/多源/真实频谱/多功能/悬停展开)→ 计划未引入,符合。

**2. 占位扫描:** 无 TODO/TBD/「add error handling」/「similar to Task N」等;每个代码步骤均含完整代码。Task 0/Task 3/Task 10/Task 18 中明确标注的「占位替换」均给出了被替换与替换后的完整内容。

**3. 类型一致性核对:**
- `NowPlayingState`/`Lyrics`/`LyricLine`/`Word`/`LyricPosition`(Task 1)在 Task 5/6/11/13 引用一致。
- `SongCandidate`/`SongQuery`/`SongMatcher.bestMatch`(Task 4)在 Task 8/10 一致。
- `LyricsParser.parse(lrc:yrc:)`(Task 2/3)在 Task 10 一致。
- `PlaybackClock(state:)`/`positionMs(at:)`(Task 6)在 Task 13 一致。
- `RawLyrics`/`NeteaseDataSource`/`NeteaseAPIClient`/`LyricsCache`/`LyricsRepository`/`LyricsLookupResult`/`NeteaseLyricsRepository`(Task 8/9/10)在 Task 13/18 一致。
- `NowPlayingProvider`/`AdapterEventDecoder.decode(line:sampledAt:neteaseBundleID:)`(Task 11)在 Task 12/13 一致。
- `AppUIState`/`PlayingDisplay`/`AppState`(Task 13)在 Task 17/18 一致。
- `NotchGeometry.panelFrame/pillFrame`(Task 14)在 Task 15 一致。
- `Settings`(Task 17)在 Task 18 一致。

> 注意一处需执行者留意:Task 0 占位写了 `public enum VanessaApp`,Task 18 要求删除它;若先做 Task 11/12/13(新建独立文件)再做 Task 18,中间阶段 `main.swift` 仍依赖占位,属预期,Task 19 修复。计划已在 Task 18 Step 2 标注此预期编译错误。
