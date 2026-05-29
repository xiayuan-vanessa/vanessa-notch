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
    public init() {}
}
