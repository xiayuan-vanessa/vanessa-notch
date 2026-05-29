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
