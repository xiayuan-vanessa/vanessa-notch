import Foundation
import VanessaCore

/// 正在播放数据源：吐 NowPlayingState 流；nil 表示空闲（无播放）。
public protocol NowPlayingProvider: AnyObject {
    /// 状态流。nil = 空闲。
    var states: AsyncStream<NowPlayingState?> { get }
    func start()
    func stop()
}

/// 播放控制命令,取值为 MediaRemote 的 MRCommand ID。
public enum MediaCommand: Int, Sendable {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

/// 把 adapter 的一行 JSON 解码成 NowPlayingState（纯函数）。
/// 接受所有播放源，不做 bundleID 过滤。
public enum AdapterEventDecoder {
    /// - Parameters:
    ///   - line: adapter stream 的一行 JSON。
    ///   - sampledAt: 收到该行的时刻（作为采样时刻）。
    /// - Returns: 解码后的状态；坏数据返回 nil。
    public static func decode(line: String, sampledAt: Date) -> NowPlayingState? {
        guard let data = line.data(using: .utf8), !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let type = obj["type"] as? String {
            guard type == "data" else { return nil }
            let payload = (obj["payload"] as? [String: Any]) ?? [:]
            return decode(payload: payload, sampledAt: sampledAt)
        }
        return decode(payload: obj, sampledAt: sampledAt)
    }

    /// 从一份 payload 字典解码。
    /// 兼容 adapter 的 `--micros` 输出:进度 / 时长优先取微秒字段;`timestampEpochMicros`
    /// 是该进度对应的真实时刻,存在时作为采样时刻(播放器可能很久没上报,收到时刻并非进度时刻),
    /// 缺失时才退回 sampledAt。
    /// - Parameter sampledAt: 收到该行的时刻,仅在 payload 无微秒时间戳时使用。
    public static func decode(payload: [String: Any], sampledAt: Date) -> NowPlayingState? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let event = try? JSONDecoder().decode(AdapterEvent.self, from: data) else { return nil }
        guard event.bundleIdentifier != nil else { return nil }
        return NowPlayingState(
            title: event.title ?? "",
            artist: event.artist ?? "",
            album: event.album ?? "",
            artworkData: event.artworkData.flatMap { Data(base64Encoded: $0) },
            duration: event.durationMicros.map { $0 / 1_000_000 } ?? event.duration ?? 0,
            elapsed: event.elapsedTimeMicros.map { $0 / 1_000_000 } ?? event.elapsedTime ?? 0,
            sampledAt: event.timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? sampledAt,
            rate: event.playbackRate ?? 1,
            isPlaying: event.playing ?? false,
            sourceBundleID: event.bundleIdentifier!
        )
    }

    /// adapter JSON 结构（仅取需要字段，全可选以容忍缺失）。
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
        let timestamp: String?
        /// 以下为 `--micros` 模式下的微秒字段。
        let durationMicros: Double?
        let elapsedTimeMicros: Double?
        let timestampEpochMicros: Double?
    }
}
