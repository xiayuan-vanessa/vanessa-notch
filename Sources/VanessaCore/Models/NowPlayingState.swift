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
