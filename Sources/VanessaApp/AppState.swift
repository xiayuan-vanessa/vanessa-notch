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
    /// 封面主色调 RGB(0...1)，用于歌词文字着色。
    public var accentR: Double
    public var accentG: Double
    public var accentB: Double
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
    public var lyricLeadMs: Double = 250

    private let provider: NowPlayingProvider
    private let repository: LyricsRepository

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

    public init(provider: NowPlayingProvider, repository: LyricsRepository) {
        self.provider = provider
        self.repository = repository
    }

    /// 启动订阅流并开启 30fps 刷新定时器。
    public func start() {
        provider.start()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.provider.states {
                await self.handle(state)
            }
        }
        startTicker()
    }

    /// 停止订阅与定时器，释放资源。
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        ticker?.invalidate()
        ticker = nil
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
            ui = .idle
            return
        }
        // 仅在时序字段变化时重建时钟，避免元数据 diff 引发位置微跳
        if latestState == nil || timingChanged(old: latestState!, new: state) {
            clock = PlaybackClock(state: state)
        }
        latestState = state
        // 封面图可能晚于元数据到达，补提取主色调（后台线程避免阻塞 UI）
        if accentRGB == nil, let data = state.artworkData {
            accentRGB = await Task.detached {
                DominantColorExtractor.extract(from: data)
            }.value
        }
        // 换歌时触发歌词拉取；duration=0 时匹配可能失败，不锁定 identity 让后续重试
        if state.songIdentity != currentIdentity {
            currentIdentity = state.songIdentity
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
            let result = try await repository.lookup(
                title: state.title,
                artist: state.artist,
                durationMs: Int(state.duration * 1000)
            )
            switch result {
            case .matched(_, let lyrics):
                currentLyrics = lyrics
                // 空歌词（纯音乐）展示占位符
                fallbackText = lyrics.isEmpty ? "♪ 纯音乐" : nil
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

    /// 启动 30fps 定时刷新，挂在 RunLoop.main 上以兼容非 UI 场景。
    private func startTicker() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// 用当前时钟位置定位歌词行，更新 UI 状态。
    func refresh() {
        guard let state = latestState, let clock else { return }
        // 提前 lyricLeadMs 补偿采样/渲染管道与感知延迟,让逐字高亮卡在字头而非滞后(可在设置调节)。
        let posMs = clock.positionMs(at: Date()) + lyricLeadMs
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
            accentR: ar, accentG: ag, accentB: ab
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
