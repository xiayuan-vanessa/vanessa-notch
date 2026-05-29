import Foundation

/// 逐字片段(YRC 中的一个字/词)。
public struct Word: Equatable, Sendable, Codable {
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public init(startMs: Int, endMs: Int, text: String) {
        self.startMs = startMs; self.endMs = endMs; self.text = text
    }
}

/// 一行歌词。words 为空表示该行无逐字信息(只能整行高亮)。
public struct LyricLine: Equatable, Sendable, Codable {
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var words: [Word]
    public init(startMs: Int, endMs: Int, text: String, words: [Word]) {
        self.startMs = startMs; self.endMs = endMs; self.text = text; self.words = words
    }
}

/// 统一歌词模型。
public struct Lyrics: Equatable, Sendable, Codable {
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
