import AppKit

/// 状态栏(菜单栏)图标:圆角"刘海/屏"轮廓内镂空三根高低错落的均衡条。
/// 以模板图(isTemplate)返回,自动适配菜单栏明/暗外观。
enum StatusBarIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            // 外框:圆角矩形(代表刘海/屏)。
            let outer = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 3.5, width: 13, height: 11.5),
                                     xRadius: 3.5, yRadius: 3.5)
            outer.windingRule = .evenOdd

            // 内部三根均衡条:用偶奇填充规则挖空(成为镂空)。
            let barWidth: CGFloat = 1.8
            let xs: [CGFloat] = [4.9, 8.1, 11.3]
            let heights: [CGFloat] = [4.0, 6.5, 5.0]
            let baseY: CGFloat = 6.0
            for (x, h) in zip(xs, heights) {
                let bar = NSBezierPath(roundedRect: NSRect(x: x, y: baseY, width: barWidth, height: h),
                                       xRadius: barWidth / 2, yRadius: barWidth / 2)
                outer.append(bar)
            }

            NSColor.black.setFill()
            outer.fill()
            return true
        }
        image.isTemplate = true   // 模板图:由系统按菜单栏外观着色
        return image
    }
}
