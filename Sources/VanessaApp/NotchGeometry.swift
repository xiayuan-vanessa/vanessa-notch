import CoreGraphics

/// 纯函数:由屏幕与刘海尺寸推算置顶窗口的全局 frame(AppKit 坐标,原点左下)。
public enum NotchGeometry {
    /// 播放面板 frame:水平居中、顶边贴齐屏幕顶,使黑色岛形与物理刘海融为一体向下展开。
    /// (notchSize 保留用于布局/未来扩展;垂直方向不再下移。)
    public static func panelFrame(screenFrame: CGRect, notchSize: CGSize, panelSize: CGSize) -> CGRect {
        hang(screenFrame: screenFrame, size: panelSize)
    }

    /// 空闲胶囊 frame:同样顶边贴齐屏幕顶、水平居中。
    public static func pillFrame(screenFrame: CGRect, notchSize: CGSize, pillSize: CGSize) -> CGRect {
        hang(screenFrame: screenFrame, size: pillSize)
    }

    /// 通用:顶边贴齐屏幕顶、水平居中放置 size 大小的窗口。
    private static func hang(screenFrame: CGRect, size: CGSize) -> CGRect {
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
