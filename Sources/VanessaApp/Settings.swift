import Foundation
import SwiftUI

/// 用户设置,持久化到 UserDefaults。
@MainActor
public final class Settings: ObservableObject {
    @AppStorage("lyricFontSize") public var fontSize: Double = 13
    @AppStorage("offsetX") public var offsetX: Double = 0
    @AppStorage("launchAtLogin") public var launchAtLogin: Bool = false
    /// 刘海面板宽度(pt)。最小约 240 以让封面/音频条避开物理刘海。
    @AppStorage("panelWidth") public var panelWidth: Double = 260
    /// 刘海面板高度(pt)。
    @AppStorage("panelHeight") public var panelHeight: Double = 80
    /// 歌词偏移(ms):正值=高亮提前。跟不上就调大。
    @AppStorage("lyricOffsetMs") public var lyricOffsetMs: Double = 250
    /// 是否在原文下方显示译文(有译文时)。
    @AppStorage("showTranslation") public var showTranslation: Bool = true
    /// 显示屏 UUID;空字符串表示「自动」(优先刘海屏)。
    @AppStorage("screenID") public var screenID: String = ""
    /// 前台应用全屏时自动隐藏刘海面板。
    @AppStorage("hideInFullscreen") public var hideInFullscreen: Bool = true
    /// 暂停多少秒后自动收起面板;0 表示不收起。
    @AppStorage("pauseHideSeconds") public var pauseHideSeconds: Double = 0
    /// 歌词顶部额外间距(pt):在自动避让刘海的基础上再下移歌词,面板同步加高。
    @AppStorage("lyricTopOffset") public var lyricTopOffset: Double = 0
    public init() {}

    /// 播放面板实际高度 = 设置的面板高度(下限 56)+ 歌词顶部额外间距。
    public var totalPanelHeight: Double {
        max(56, panelHeight) + lyricTopOffset
    }
}
