import Foundation
import VanessaCore

/// 歌词缓存:内存字典(快)+ 磁盘 JSON(跨进程持久)。按歌曲 ID。线程安全(串行队列)。
public final class LyricsCache: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "vanessa.lyrics-cache")
    private var memory: [Int64: Lyrics] = [:]

    /// - Parameter directory: 缓存目录;默认 Application Support/VanessaNotch/lyrics-v2。
    ///   (v2 起缓存包含译文;换目录让旧缓存失效,避免已缓存歌曲永远没有译文。)
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("VanessaNotch/lyrics-v2", isDirectory: true)
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

    /// 匹配结果缓存(查询键 → 歌曲 ID);首次访问时从磁盘懒加载。
    private var matches: [String: Int64]?

    /// 读取某次查询已匹配到的歌曲 ID;未命中返回 nil。
    /// - Parameter key: 查询键,由仓储层按「歌名 + 歌手 + 时长」拼成。
    public func songID(forQuery key: String) -> Int64? {
        queue.sync { loadedMatches()[key] }
    }

    /// 记录查询的匹配结果,并整体写回磁盘。
    public func storeSongID(_ id: Int64, forQuery key: String) {
        queue.sync {
            var dict = loadedMatches()
            dict[key] = id
            matches = dict
            if let data = try? JSONEncoder().encode(dict) {
                try? data.write(to: matchesURL, options: .atomic)
            }
        }
    }

    /// 返回内存中的匹配表,首次调用时从磁盘读取(文件缺失或损坏视为空表)。须在 queue 内调用。
    private func loadedMatches() -> [String: Int64] {
        if let matches { return matches }
        let loaded = (try? Data(contentsOf: matchesURL))
            .flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) } ?? [:]
        matches = loaded
        return loaded
    }

    /// 匹配表文件;与 `<歌曲ID>.json` 同目录,文件名非数字不会冲突。
    private var matchesURL: URL {
        directory.appendingPathComponent("matches.json")
    }

    private func fileURL(_ id: Int64) -> URL {
        directory.appendingPathComponent("\(id).json")
    }
}
