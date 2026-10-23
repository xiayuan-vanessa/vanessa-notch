import Foundation

/// 按歌曲保存的个性化设置:手动指定的网易云歌曲 ID、单曲歌词偏移。
/// 以 NowPlayingState.songIdentity 为键,持久化到 UserDefaults。
@MainActor
public final class SongPreferences {
    private let defaults: UserDefaults
    private static let songIDsKey = "songManualIDs"
    private static let offsetsKey = "songOffsetsMs"

    /// - Parameter defaults: 存储位置;测试可注入独立 suite 避免污染真实设置。
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 手动指定的歌曲 ID;未指定返回 nil。
    public func songID(for identity: String) -> Int64? {
        (defaults.dictionary(forKey: Self.songIDsKey)?[identity] as? NSNumber)?.int64Value
    }

    /// 记录手动指定的歌曲 ID。
    public func setSongID(_ id: Int64, for identity: String) {
        var dict = defaults.dictionary(forKey: Self.songIDsKey) ?? [:]
        dict[identity] = NSNumber(value: id)
        defaults.set(dict, forKey: Self.songIDsKey)
    }

    /// 单曲歌词偏移(毫秒,叠加在全局偏移上);未设置返回 0。
    public func offsetMs(for identity: String) -> Double {
        (defaults.dictionary(forKey: Self.offsetsKey)?[identity] as? NSNumber)?.doubleValue ?? 0
    }

    /// 记录单曲偏移;为 0 时删除该条,避免字典无限增长。
    public func setOffsetMs(_ ms: Double, for identity: String) {
        var dict = defaults.dictionary(forKey: Self.offsetsKey) ?? [:]
        dict[identity] = ms == 0 ? nil : NSNumber(value: ms)
        defaults.set(dict, forKey: Self.offsetsKey)
    }
}
