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
    /// 累积的完整 payload(diff 增量行会合并进来,full 行会整体替换)。
    private var merged: [String: Any] = [:]

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
                merged.merge(payload) { _, new in new }   // 增量:合并变化字段
            } else {
                merged = payload                           // 完整快照:整体替换
            }
            let state = AdapterEventDecoder.decode(payload: merged, sampledAt: Date(), neteaseBundleID: neteaseBundleID)
            continuation.yield(state)
        }
    }
}
