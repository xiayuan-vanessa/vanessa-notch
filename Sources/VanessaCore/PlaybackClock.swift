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
