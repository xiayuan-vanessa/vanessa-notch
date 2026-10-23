import SwiftUI

/// 设置弹窗:字号、位置微调、开机启动、状态说明、退出。
struct SettingsView: View {
    @ObservedObject var settings: Settings
    let adapterAvailable: Bool
    var onQuit: () -> Void

    var body: some View {
        Form {
            if !adapterAvailable {
                Section("状态") {
                    Label("无法读取系统正在播放信息。请确认已授权,或重启 App 重试。",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            Section("歌词") {
                Slider(value: $settings.fontSize, in: 10...20, step: 1) { Text("字号") }
                Toggle("显示译文", isOn: $settings.showTranslation)
                Slider(value: $settings.offsetX, in: -200...200, step: 1) { Text("水平微调") }
                Slider(value: $settings.lyricTopOffset, in: 0...20, step: 1) {
                    Text("顶部间距")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("20") }
                Text("顶部间距:\(Int(settings.lyricTopOffset)) pt(歌词顶着刘海就调大,面板会同步加高)")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $settings.lyricOffsetMs, in: -1000...1000, step: 10) {
                    Text("歌词偏移")
                } minimumValueLabel: { Text("-1s") } maximumValueLabel: { Text("+1s") }
                Text("偏移:\(Int(settings.lyricOffsetMs)) ms(跟不上就调大,超前就调小)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("面板尺寸") {
                Slider(value: $settings.panelWidth, in: 240...460, step: 2) {
                    Text("宽度")
                } minimumValueLabel: { Text("240") } maximumValueLabel: { Text("460") }
                Text("宽度:\(Int(settings.panelWidth)) pt").font(.caption).foregroundStyle(.secondary)
                Slider(value: $settings.panelHeight, in: 56...160, step: 2) {
                    Text("高度")
                } minimumValueLabel: { Text("56") } maximumValueLabel: { Text("160") }
                Text("高度:\(Int(settings.panelHeight)) pt").font(.caption).foregroundStyle(.secondary)
            }
            Section("显示") {
                Picker("显示屏幕", selection: $settings.screenID) {
                    Text("自动(优先刘海屏)").tag("")
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        if let id = NotchWindowController.screenID(of: screen) {
                            Text(screen.localizedName).tag(id)
                        }
                    }
                }
                Toggle("全屏应用时自动隐藏", isOn: $settings.hideInFullscreen)
            }
            Section("通用") {
                Toggle("开机启动", isOn: $settings.launchAtLogin)
                Button("退出 Vanessa-Notch", role: .destructive, action: onQuit)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 520)
    }
}
