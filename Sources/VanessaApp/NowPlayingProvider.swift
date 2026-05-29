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
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // adapter 实际输出为信封格式:{"type":"data","diff":Bool,"payload":{...字段...}}。
        if let type = obj["type"] as? String {
            guard type == "data" else { return nil }
            let payload = (obj["payload"] as? [String: Any]) ?? [:]
            return decode(payload: payload, sampledAt: sampledAt, neteaseBundleID: neteaseBundleID)
        }
        // 兼容:无信封时把整个对象直接当作 payload。
        return decode(payload: obj, sampledAt: sampledAt, neteaseBundleID: neteaseBundleID)
    }

    /// 从一份 payload 字典解码(provider 会先把多行增量合并成完整 payload 再调用)。
    /// - Returns: 非网易云来源或缺少 bundleIdentifier 时返回 nil。
    public static func decode(payload: [String: Any], sampledAt: Date, neteaseBundleID: String) -> NowPlayingState? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let event = try? JSONDecoder().decode(AdapterEvent.self, from: data) else { return nil }
        let isNetease = event.bundleIdentifier == neteaseBundleID
            || event.parentApplicationBundleIdentifier == neteaseBundleID
        guard isNetease else { return nil }
        // 采样时刻优先用 adapter 的 timestamp(elapsedTime 是该时刻的进度);
        // 缺失时退回传入的 sampledAt。这样播放中途接入也能正确推算实时进度。
        let sample = event.timestamp.flatMap(parseTimestamp) ?? sampledAt
        return NowPlayingState(
            title: event.title ?? "",
            artist: event.artist ?? "",
            album: event.album ?? "",
            artworkData: event.artworkData.flatMap { Data(base64Encoded: $0) },
            duration: event.duration ?? 0,
            elapsed: event.elapsedTime ?? 0,
            sampledAt: sample,
            rate: event.playbackRate ?? 1,
            isPlaying: event.playing ?? false,
            sourceBundleID: event.bundleIdentifier ?? neteaseBundleID
        )
    }

    /// 解析 ISO8601 时间戳(兼容带/不带小数秒)。
    static func parseTimestamp(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
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
        let timestamp: String?
    }
}
