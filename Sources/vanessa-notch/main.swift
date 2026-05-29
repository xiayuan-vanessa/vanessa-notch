import AppKit
import VanessaApp

// 菜单栏代理:无 Dock 图标(.accessory)。LSUIElement 由打包脚本写入 Info.plist。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
