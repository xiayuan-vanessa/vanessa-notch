import Foundation
import SwiftUI
import VanessaCore
import VanessaNetease

/// 面板展示数据。
public struct PlayingDisplay: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var artworkData: Data?
    /// 当前行文本 / 「♪ 纯音乐」 / 「歌名 - 歌手」降级文案
    public var lineText: String
    /// 当前行译文;无译文或处于降级文案时为 nil
    public var translation: String?
    /// 逐字高亮数据(空数组表示整行高亮)
    public var words: [Word]
    public var position: LyricPosition
    public var isPlaying: Bool
    /// 当前播放进度(秒,不含歌词提前量),供控制面板进度条显示。
    public var elapsed: Double = 0
    /// 歌曲总时长(秒);未知时为 0。
    public var duration: Double = 0
    /// 封面主色调 RGB(0...1)，用于歌词文字着色。
    public var accentR: Double
    public var accentG: Double
    public var accentB: Double
    /// 完整歌词行,供完整歌词列表展示;处于降级文案(无歌词/纯音乐)时为空。
    public var lines: [LyricLine] = []
}

/// 全局 UI 状态。
public enum AppUIState: Equatable, Sendable {
    case idle
    case warning(message: String)
    case playing(PlayingDisplay)
}

/// 编排层:订阅 provider 状态流 → 换歌时异步拉歌词 → 30fps tick 计算高亮 → 输出 AppUIState。
@MainActor
public final class AppState: ObservableObject {
    /// 对外暴露的 UI 状态，视图直接绑定。
    @Published public private(set) var ui: AppUIState = .idle

    /// 歌词提前量(毫秒):正值让逐字高亮提前,补偿管道/感知延迟。由设置实时调节。
    /// 暂停时定时器不运行,因此变更后主动刷新一次,让调节立即可见。
    public var lyricLeadMs: Double = 250 {
        didSet { if lyricLeadMs != oldValue { refresh() } }
    }

    /// 暂停多少秒后自动收起面板;0 表示不收起。由设置实时调节。
    /// 变更时按新值重新计时(暂停中改为 0 会立即恢复面板)。
    public var pauseHideDelay: TimeInterval = 0 {
        didSet {
            guard pauseHideDelay != oldValue else { return }
            cancelPauseHide()
            if let state = latestState, !state.isPlaying { schedulePauseHide() }
            refresh()
        }
    }
    /// 是否因暂停超时而收起面板;为 true 时 refresh 只输出 .idle。
    private var hiddenForPause = false
    /// 暂停超时收起的计时任务。
    private var pauseHideTask: Task<Void, Never>?

    private let provider: NowPlayingProvider
    private let repository: LyricsRepository
    private let preferences: SongPreferences
    /// 当前歌曲的单曲偏移(毫秒),叠加在 lyricLeadMs 上。
    private var songOffsetMs: Double = 0

    /// 当前歌曲的唯一标识，用于判断是否换歌。
    /// 当前封面主色调 RGB；nil 时使用默认色。
    private var accentRGB: (r: Double, g: Double, b: Double)?

    private var currentIdentity: String?
    /// 当前歌词数据。
    private var currentLyrics: Lyrics = Lyrics(lines: [])
    /// 非 nil 时直接展示该降级文案，不走歌词定位。
    private var fallbackText: String?
    /// 当前播放时钟，用于推算当前进度。
    private var clock: PlaybackClock?
    /// 最后收到的播放状态，供 refresh 读取元数据。
    private var latestState: NowPlayingState?
    /// 状态流消费任务。
    private var streamTask: Task<Void, Never>?
    /// 30fps 刷新定时器。
    private var ticker: Timer?

    public init(provider: NowPlayingProvider, repository: LyricsRepository,
                preferences: SongPreferences = SongPreferences()) {
        self.provider = provider
        self.repository = repository
        self.preferences = preferences
    }

    /// 启动订阅流。30fps 刷新定时器在收到「播放中」状态时才启动(见 updatePlaybackActivity)。
    public func start() {
        provider.start()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.provider.states {
                await self.handle(state)
            }
        }
    }

    /// 停止订阅与定时器，释放资源。
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        stopTicker()
        cancelPauseHide()
        provider.stop()
    }

    /// 处理一条来源状态：nil 重置为 idle；换歌则异步拉取歌词；否则仅更新时钟。
    func handle(_ state: NowPlayingState?) async {
        guard let state else {
            // 播放停止，重置所有状态
            currentIdentity = nil
            latestState = nil
            clock = nil
            accentRGB = nil
            stopTicker()
            cancelPauseHide()
            hiddenForPause = false
            ui = .idle
            return
        }
        // 仅在时序字段变化时重建时钟，避免元数据 diff 引发位置微跳
        if latestState == nil || timingChanged(old: latestState!, new: state) {
            clock = PlaybackClock(state: state)
        }
        latestState = state
        updatePlaybackActivity(isPlaying: state.isPlaying)
        // 封面图可能晚于元数据到达，补提取主色调（后台线程避免阻塞 UI）
        if accentRGB == nil, let data = state.artworkData {
            accentRGB = await Task.detached {
                DominantColorExtractor.extract(from: data)
            }.value
        }
        // 换歌时触发歌词拉取；duration=0 时匹配可能失败，不锁定 identity 让后续重试
        if state.songIdentity != currentIdentity {
            currentIdentity = state.songIdentity
            songOffsetMs = preferences.offsetMs(for: state.songIdentity)
            await loadLyrics(for: state)
            if fallbackText != nil && state.duration <= 0 {
                currentIdentity = nil
            }
        }
        refresh()
    }

    /// 异步拉取歌词：matched 填充 lyrics；低置信度或异常降级为「歌名 - 歌手」。
    private func loadLyrics(for state: NowPlayingState) async {
        // 立即清空旧歌词，用新歌降级文案过渡，避免异步间隙中旧内容闪现
        currentLyrics = Lyrics(lines: [])
        fallbackText = "\(state.title) - \(state.artist)"

        // 提取封面主色调（后台线程避免阻塞 UI）
        if let data = state.artworkData {
            accentRGB = await Task.detached {
                DominantColorExtractor.extract(from: data)
            }.value
        } else {
            accentRGB = nil
        }
        do {
            // 用户手动指定过歌曲:跳过自动匹配,直接按 ID 取歌词
            if let manualID = preferences.songID(for: state.songIdentity) {
                show(try await repository.lyrics(forSongID: manualID))
                return
            }
            let result = try await repository.lookup(
                title: state.title,
                artist: state.artist,
                durationMs: Int(state.duration * 1000)
            )
            switch result {
            case .matched(_, let lyrics):
                show(lyrics)
            case .lowConfidence:
                currentLyrics = Lyrics(lines: [])
                fallbackText = "\(state.title) - \(state.artist)"
            }
        } catch {
            // 网络或解析失败，降级显示歌名 - 歌手
            currentLyrics = Lyrics(lines: [])
            fallbackText = "\(state.title) - \(state.artist)"
        }
    }

    /// 展示匹配到的歌词;空歌词(纯音乐)展示占位符。
    private func show(_ lyrics: Lyrics) {
        currentLyrics = lyrics
        fallbackText = lyrics.isEmpty ? "♪ 纯音乐" : nil
    }

    // MARK: - 手动校正

    /// 当前歌曲信息(供校正窗口预填);未在播放时为 nil。
    public var currentSong: (identity: String, title: String, artist: String)? {
        latestState.map { ($0.songIdentity, $0.title, $0.artist) }
    }

    /// 按关键词搜索候选歌曲。
    public func searchCandidates(_ keywords: String) async throws -> [SongCandidate] {
        try await repository.search(keywords: keywords)
    }

    /// 手动指定某首歌对应的网易云歌曲:拉取歌词并记住选择;若该歌仍在播放则立即替换显示。
    /// - Throws: 拉取歌词失败时抛出,此时不记录选择。
    public func applyManualMatch(songID: Int64, for identity: String) async throws {
        let lyrics = try await repository.lyrics(forSongID: songID)
        preferences.setSongID(songID, for: identity)
        guard latestState?.songIdentity == identity else { return }   // 期间已切歌
        show(lyrics)
        refresh()
    }

    /// 读取某首歌的单曲偏移(毫秒)。
    public func songOffset(for identity: String) -> Double {
        preferences.offsetMs(for: identity)
    }

    /// 设置某首歌的单曲偏移;若该歌正在播放则立即生效(暂停中也刷新一次,让调节立即可见)。
    public func setSongOffset(_ ms: Double, for identity: String) {
        preferences.setOffsetMs(ms, for: identity)
        if latestState?.songIdentity == identity {
            songOffsetMs = ms
            refresh()
        }
    }

    // MARK: - 跳转

    /// 跳转后的本地乐观更新:立即按目标进度重建时钟并刷新,让进度条与歌词马上跟上,
    /// 不必等播放器回报(回报到达且时序字段变化时照常重建时钟,以真实进度为准)。
    /// 实际向播放器发送跳转命令由调用方负责。
    /// - Parameter seconds: 目标进度(秒);越界时夹到 [0, 总时长]。未在播放时忽略。
    public func applySeek(toSeconds seconds: Double) {
        guard let state = latestState else { return }
        let upper = state.duration > 0 ? state.duration : max(seconds, 0)
        let target = min(max(seconds, 0), upper)
        clock = PlaybackClock(elapsed: target, sampledAt: Date(), rate: state.rate,
                              isPlaying: state.isPlaying, duration: state.duration)
        refresh()
    }

    /// 计算跳转到某行歌词时应发给播放器的进度(秒)。
    /// 歌词定位使用「播放进度 + 全局提前量 + 本歌偏移」,因此目标进度要减去这两项,
    /// 跳转后该行恰好成为当前行。
    /// - Parameter startMs: 目标行的起始时间(毫秒,歌词时间轴)
    /// - Returns: 播放器进度(秒),不小于 0
    public func seekSeconds(forLineStartMs startMs: Int) -> Double {
        max(Double(startMs) - lyricLeadMs - songOffsetMs, 0) / 1000
    }

    // MARK: - 播放/暂停联动

    /// 按播放状态切换刷新定时器与暂停收起计时:
    /// 播放中 → 启动定时器、取消收起计时并恢复面板;暂停 → 停掉定时器(进度不再前进,无需逐帧刷新)并开始收起计时。
    private func updatePlaybackActivity(isPlaying: Bool) {
        if isPlaying {
            if ticker == nil { startTicker() }
            cancelPauseHide()
            hiddenForPause = false
        } else {
            stopTicker()
            if pauseHideTask == nil && !hiddenForPause { schedulePauseHide() }
        }
    }

    /// 开始暂停收起计时:pauseHideDelay 秒后标记收起并切到 .idle。延时为 0 时不计时。
    private func schedulePauseHide() {
        guard pauseHideDelay > 0 else { return }
        let delay = pauseHideDelay
        pauseHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }   // 期间已恢复播放或重置
            self.pauseHideTask = nil
            self.hiddenForPause = true
            self.refresh()
        }
    }

    /// 取消尚未触发的暂停收起计时(不改变已收起状态)。
    private func cancelPauseHide() {
        pauseHideTask?.cancel()
        pauseHideTask = nil
    }

    /// 刷新定时器是否在运行;仅供测试断言。
    var isTickerRunning: Bool { ticker != nil }

    /// 启动 30fps 定时刷新，挂在 RunLoop.main 上以兼容非 UI 场景。
    private func startTicker() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// 停止刷新定时器。
    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// 用当前时钟位置定位歌词行，更新 UI 状态。
    func refresh() {
        guard let state = latestState, let clock else { return }
        // 暂停超时已收起:保持空闲胶囊,恢复播放时 hiddenForPause 被清除后再正常输出
        if hiddenForPause {
            if ui != .idle { ui = .idle }
            return
        }
        // 提前 lyricLeadMs 补偿采样/渲染管道与感知延迟,让逐字高亮卡在字头而非滞后(可在设置调节)。
        let rawMs = clock.positionMs(at: Date())
        let posMs = rawMs + lyricLeadMs + songOffsetMs
        let position = LyricSyncEngine.locate(positionMs: posMs, in: currentLyrics)

        let lineText: String
        let words: [Word]
        var translation: String?

        if let fb = fallbackText {
            // 降级文案：直接展示，不走歌词定位
            lineText = fb
            words = []
        } else if let idx = position.lineIndex, idx < currentLyrics.lines.count {
            // 正常歌词定位成功
            lineText = currentLyrics.lines[idx].text
            words = currentLyrics.lines[idx].words
            translation = currentLyrics.lines[idx].translation
        } else {
            // 定位未命中（例如进度在第一行之前），展示第一行或降级
            lineText = currentLyrics.lines.first?.text ?? "\(state.title) - \(state.artist)"
            words = []
        }

        let ar = accentRGB?.r ?? 229.0 / 255
        let ag = accentRGB?.g ?? 199.0 / 255
        let ab = accentRGB?.b ?? 192.0 / 255
        let next = AppUIState.playing(PlayingDisplay(
            title: state.title,
            artist: state.artist,
            artworkData: state.artworkData,
            lineText: lineText,
            translation: translation,
            words: words,
            position: position,
            isPlaying: state.isPlaying,
            elapsed: max(rawMs / 1000, 0),
            duration: state.duration,
            accentR: ar, accentG: ag, accentB: ab,
            lines: fallbackText == nil ? currentLyrics.lines : []
        ))
        // 内容未变(如暂停中)不重复发布,避免每秒 30 次无意义的视图刷新
        if next != ui { ui = next }
    }

    /// 判断两次状态之间时序相关字段是否有变化。
    private func timingChanged(old: NowPlayingState, new: NowPlayingState) -> Bool {
        old.elapsed != new.elapsed
            || old.sampledAt != new.sampledAt
            || old.rate != new.rate
            || old.isPlaying != new.isPlaying
    }

    /// 标记 provider 不可用，进入警告态（由 AppDelegate 在 provider 初始化失败时调用）。
    public func markUnavailable(message: String) {
        ui = .warning(message: message)
    }

    /// 测试辅助：让出当前任务，等待已投喂的状态被异步消费完。
    /// 正式代码不应依赖此方法。
    public func drainForTesting() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}
