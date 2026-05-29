import AppKit

// 绘制 1024x1024 App 图标主图:深色圆角底 + 顶部刘海 + 玫瑰色(#E5C7C0)均衡条。
// 输出路径由命令行参数给出。
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/appicon_1024.png"
let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("ctx")
}

let accent = CGColor(red: 229/255, green: 199/255, blue: 192/255, alpha: 1) // #E5C7C0

// 圆角方形裁剪(macOS 风格大圆角)
let corner: CGFloat = 230
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                   cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()

// 深色竖向渐变底
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1),
    CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// 顶部刘海:纯黑、上方平、下方圆角,底沿描一道玫瑰色细边以在深色底上可见
let notchW: CGFloat = 300, notchH: CGFloat = 110, nr: CGFloat = 52
let nx = (S - notchW) / 2, ny = S - notchH
let np = CGMutablePath()
np.move(to: CGPoint(x: nx, y: S))
np.addLine(to: CGPoint(x: nx + notchW, y: S))
np.addLine(to: CGPoint(x: nx + notchW, y: ny + nr))
np.addQuadCurve(to: CGPoint(x: nx + notchW - nr, y: ny), control: CGPoint(x: nx + notchW, y: ny))
np.addLine(to: CGPoint(x: nx + nr, y: ny))
np.addQuadCurve(to: CGPoint(x: nx, y: ny + nr), control: CGPoint(x: nx, y: ny))
np.closeSubpath()
ctx.addPath(np); ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fillPath()
ctx.addPath(np); ctx.setStrokeColor(accent); ctx.setLineWidth(7); ctx.strokePath()

// 主体:5 根玫瑰色圆头均衡条,垂直居中于下方主区
let barW: CGFloat = 76
let gap: CGFloat = 46
let heights: [CGFloat] = [210, 360, 265, 390, 235]
let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = (S - total) / 2
let midY: CGFloat = 460
ctx.setFillColor(accent)
for h in heights {
    let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
    ctx.fillPath()
    x += barW + gap
}

guard let img = ctx.makeImage(),
      let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                "public.png" as CFString, 1, nil) else {
    fatalError("write")
}
CGImageDestinationAddImage(dst, img, nil)
CGImageDestinationFinalize(dst)
print("wrote \(outPath)")
