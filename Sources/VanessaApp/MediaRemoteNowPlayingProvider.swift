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
    private var process: Process?
    private var buffer = Data()
    /// 累积的完整 payload(diff 增量行会合并进来,full 行会整体替换)。
    private var merged: [String: Any] = [:]

    /// adapter 是否可用(脚本/framework 是否就绪)。供 UI 显示「警告态」。
    public private(set) var isAvailable: Bool = true

    /// - Parameters:
    ///   - scriptPath: 内嵌的 mediaremote-adapter.pl 绝对路径。
    ///   - frameworkPath: 内嵌的 MediaRemoteAdapter.framework 绝对路径。
    public init(scriptPath: String, frameworkPath: String,
                perlPath: String = "/usr/bin/perl") {
        self.perlPath = perlPath
        self.scriptPath = scriptPath
        self.frameworkPath = frameworkPath
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
        // --micros:输出微秒精度的进度与进度对应时刻(timestampEpochMicros),用于准确推算当前进度
        proc.arguments = [scriptPath, frameworkPath, "stream", "--micros"]
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

    /// 向当前播放应用发送播放控制命令(经 adapter 的 send 子命令,一次性短进程)。
    /// 资源缺失或进程启动失败时仅记录日志,不影响歌词流。
    public func send(_ command: MediaCommand) {
        guard FileManager.default.fileExists(atPath: scriptPath),
              FileManager.default.fileExists(atPath: frameworkPath) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: perlPath)
        proc.arguments = [scriptPath, frameworkPath, "send", String(command.rawValue)]
        do {
            try proc.run()
        } catch {
            NSLog("[Vanessa-Notch] 发送播放命令 %d 失败: %@", command.rawValue, String(describing: error))
        }
    }

    /// 让当前播放应用跳转到指定进度(经 adapter 的 seek 子命令,一次性短进程)。
    /// - Parameter seconds: 目标进度(秒);负值按 0 处理。
    /// 资源缺失或进程启动失败时仅记录日志。
    public func seek(toSeconds seconds: Double) {
        guard FileManager.default.fileExists(atPath: scriptPath),
              FileManager.default.fileExists(atPath: frameworkPath) else { return }
        let micros = Int64(max(seconds, 0) * 1_000_000)   // adapter 的 seek 参数单位为微秒
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: perlPath)
        proc.arguments = [scriptPath, frameworkPath, "seek", String(micros)]
        do {
            try proc.run()
        } catch {
            NSLog("[Vanessa-Notch] 跳转到 %.1f 秒失败: %@", seconds, String(describing: error))
        }
    }

    /// 累积字节,按换行切分;按 adapter 信封合并 full/diff 行,解码后推流。
    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        let newline = UInt8(ascii: "\n")
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (obj["type"] as? String) == "data" else { continue }
            let payload = (obj["payload"] as? [String: Any]) ?? [:]
            if (obj["diff"] as? Bool) == true {
                merged.merge(payload) { _, new in new }
            } else {
                merged = payload
            }
            let state = AdapterEventDecoder.decode(payload: merged, sampledAt: Date())
            continuation.yield(state)
        }
    }
}
