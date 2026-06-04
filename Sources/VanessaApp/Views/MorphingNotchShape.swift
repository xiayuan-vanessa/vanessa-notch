import SwiftUI

/// 可动画形状：在居中小胶囊(progress=0)与全尺寸刘海岛(progress=1)之间平滑插值。
/// 用于刘海区域的展开/收起过渡动画。
struct MorphingNotchShape: Shape, Animatable {
    /// 变形进度：0 = 胶囊, 1 = 圆角矩形岛
    var progress: Double

    /// 胶囊（收起态）的固定宽度
    static let pillWidth: CGFloat = 140
    /// 胶囊（收起态）的固定高度
    static let pillHeight: CGFloat = 22

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // 将 progress 限制在 [0, 1] 范围内
        let t = min(max(progress, 0), 1)

        // 插值计算当前尺寸
        let w = lerp(Self.pillWidth, rect.width, t)
        let h = lerp(Self.pillHeight, rect.height, t)

        // 插值计算圆角半径
        // 顶部：胶囊全圆角(11) → 面板方角(0)
        let topR = lerp(11, 0, t)
        // 底部：胶囊全圆角(11) → 面板 18pt 圆角
        let bottomR = lerp(11, 18, t)

        // 水平居中、顶部对齐
        let x = rect.minX + (rect.width - w) / 2
        let y = rect.minY

        return buildPath(x: x, y: y, w: w, h: h,
                         topR: topR, bottomR: bottomR)
    }

    /// 构建带四个独立圆角的矩形路径
    /// - Parameters:
    ///   - x: 矩形左上角 x 坐标
    ///   - y: 矩形左上角 y 坐标
    ///   - w: 矩形宽度
    ///   - h: 矩形高度
    ///   - topR: 顶部圆角半径
    ///   - bottomR: 底部圆角半径
    /// - Returns: 顺时针方向从左上角开始的闭合路径
    private func buildPath(
        x: CGFloat, y: CGFloat,
        w: CGFloat, h: CGFloat,
        topR: CGFloat, bottomR: CGFloat
    ) -> Path {
        var path = Path()

        // 顺时针方向，从左上角开始

        // 左上角
        if topR < 0.5 {
            // 退化为直线，避免微小弧线
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.move(to: CGPoint(x: x, y: y + topR))
            path.addQuadCurve(
                to: CGPoint(x: x + topR, y: y),
                control: CGPoint(x: x, y: y)
            )
        }

        // 右上角
        if topR < 0.5 {
            path.addLine(to: CGPoint(x: x + w, y: y))
        } else {
            path.addLine(to: CGPoint(x: x + w - topR, y: y))
            path.addQuadCurve(
                to: CGPoint(x: x + w, y: y + topR),
                control: CGPoint(x: x + w, y: y)
            )
        }

        // 右下角
        path.addLine(to: CGPoint(x: x + w, y: y + h - bottomR))
        path.addQuadCurve(
            to: CGPoint(x: x + w - bottomR, y: y + h),
            control: CGPoint(x: x + w, y: y + h)
        )

        // 左下角
        path.addLine(to: CGPoint(x: x + bottomR, y: y + h))
        path.addQuadCurve(
            to: CGPoint(x: x, y: y + h - bottomR),
            control: CGPoint(x: x, y: y + h)
        )

        path.closeSubpath()
        return path
    }

    /// 线性插值
    /// - Parameters:
    ///   - a: 起始值（t=0 时）
    ///   - b: 结束值（t=1 时）
    ///   - t: 插值因子 [0, 1]
    /// - Returns: 插值结果
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
}
