# 专辑色主题 + 灵动岛变形动画 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 歌词文字颜色跟随封面主色变化 + 空闲/播放状态切换时形状平滑变形过渡

**Architecture:** 功能 1 在 VanessaCore 新增纯函数颜色提取器，通过 AppState → PlayingDisplay → KaraokeLineView 传递 RGB。功能 2 在 Views 层新增可动画 Shape，RootView 改为统一变形容器，AppDelegate 协调窗口尺寸与动画时序。

**Tech Stack:** Swift, SwiftUI, CoreGraphics, ImageIO

---

## 文件变更总览

| 操作 | 文件 | 职责 |
|------|------|------|
| 新建 | `Sources/VanessaCore/DominantColorExtractor.swift` | 从图片数据提取主色调 RGB |
| 新建 | `Tests/VanessaCoreTests/DominantColorExtractorTests.swift` | 颜色提取器单元测试 |
| 修改 | `Sources/VanessaApp/AppState.swift` | 新增 accentRGB 属性，换歌时提取颜色 |
| 修改 | `Sources/VanessaApp/Views/KaraokeLineView.swift` | 接收 accentColor 参数替代硬编码色 |
| 修改 | `Sources/VanessaApp/Views/PlayingPanelView.swift` | 透传 accentColor 到 KaraokeLineView |
| 新建 | `Sources/VanessaApp/Views/MorphingNotchShape.swift` | 胶囊↔圆角矩形可动画形状 |
| 新建 | `Tests/VanessaAppTests/MorphingNotchShapeTests.swift` | 变形形状单元测试 |
| 修改 | `Sources/VanessaApp/Views/RootView.swift` | 统一变形容器，驱动 morphProgress |
| 修改 | `Sources/VanessaApp/NotchWindowController.swift` | 新增延迟收缩方法 |
| 修改 | `Sources/VanessaApp/AppDelegate.swift` | 协调窗口尺寸与动画时序 |

---

## Task 1: DominantColorExtractor 颜色提取器

**Files:**
- Create: `Sources/VanessaCore/DominantColorExtractor.swift`
- Test: `Tests/VanessaCoreTests/DominantColorExtractorTests.swift`

### Step 1: 编写测试

```swift
// Tests/VanessaCoreTests/DominantColorExtractorTests.swift
import XCTest
import CoreGraphics
import ImageIO
@testable import VanessaCore

final class DominantColorExtractorTests: XCTestCase {

    /// 生成指定颜色的 4x4 纯色 PNG 数据。
    private func solidPNG(r: UInt8, g: UInt8, b: UInt8) -> Data {
        let size = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: CGFloat(r)/255, green: CGFloat(g)/255,
                         blue: CGFloat(b)/255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let cgImage = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithData(NSMutableData() as CFMutableData,
                                                     "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        // 用 ImageIO 编码为 PNG data
        let mdata = NSMutableData()
        let d = CGImageDestinationCreateWithData(mdata, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(d, cgImage, nil)
        CGImageDestinationFinalize(d)
        return mdata as Data
    }

    func test_solidRed_extractsRed() {
        let data = solidPNG(r: 220, g: 50, b: 50)
        let result = DominantColorExtractor.extract(from: data)
        XCTAssertNotNil(result)
        guard let rgb = result else { return }
        XCTAssertGreaterThan(rgb.r, 0.7)
        XCTAssertLessThan(rgb.g, 0.4)
        XCTAssertLessThan(rgb.b, 0.4)
    }

    func test_solidBlack_returnsNil() {
        let data = solidPNG(r: 0, g: 0, b: 0)
        XCTAssertNil(DominantColorExtractor.extract(from: data))
    }

    func test_invalidData_returnsNil() {
        let garbage = Data([0x00, 0x01, 0x02])
        XCTAssertNil(DominantColorExtractor.extract(from: garbage))
    }

    func test_solidGray_returnsNil() {
        let data = solidPNG(r: 128, g: 128, b: 128)
        XCTAssertNil(DominantColorExtractor.extract(from: data))
    }

    func test_solidBlue_extractsBlue() {
        let data = solidPNG(r: 30, g: 80, b: 220)
        let result = DominantColorExtractor.extract(from: data)
        XCTAssertNotNil(result)
        guard let rgb = result else { return }
        XCTAssertLessThan(rgb.r, 0.3)
        XCTAssertGreaterThan(rgb.b, 0.6)
    }
}
```

### Step 2: 运行测试确认失败

Run: `swift test --filter DominantColorExtractorTests`
Expected: 编译失败，`DominantColorExtractor` 未定义

### Step 3: 实现 DominantColorExtractor

```swift
// Sources/VanessaCore/DominantColorExtractor.swift
import Foundation
import CoreGraphics
import ImageIO

/// 从图片数据提取主色调 RGB(纯函数，无副作用)。
/// 返回 nil 表示提取失败(无效数据 / 纯黑 / 纯灰)。
public enum DominantColorExtractor {
    public static func extract(from imageData: Data) -> (r: Double, g: Double, b: Double)? {
        guard let cgImage = decodeImage(imageData) else { return nil }
        guard let pixels = downsample(cgImage, to: 32) else { return nil }
        return dominantColor(from: pixels, count: 32 * 32)
    }

    /// Data → CGImage。
    private static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 缩采样到 size×size，返回 RGBA 像素指针。
    private static func downsample(_ image: CGImage, to size: Int) -> UnsafeMutablePointer<UInt8>? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.data?.bindMemory(to: UInt8.self, capacity: size * size * 4)
    }

    /// 从像素数据中提取最饱和的主色。
    /// 按色相分 12 个桶(各 30°)，以饱和度加权累计，取权重最大的桶。
    private static func dominantColor(from pixels: UnsafeMutablePointer<UInt8>,
                                       count: Int) -> (r: Double, g: Double, b: Double)? {
        // (rSum, gSum, bSum, satWeight) per bucket
        var buckets = Array(repeating: (rSum: 0.0, gSum: 0.0, bSum: 0.0, weight: 0.0), count: 12)

        for i in 0..<count {
            let o = i * 4
            let r = Double(pixels[o]) / 255, g = Double(pixels[o+1]) / 255, b = Double(pixels[o+2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
            let sat = maxC == 0 ? 0 : delta / maxC
            // 过滤低亮度和低饱和度
            guard maxC >= 0.3, sat >= 0.15 else { continue }

            var hue = 0.0
            if delta > 0 {
                if maxC == r { hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
                else if maxC == g { hue = 60 * ((b - r) / delta + 2) }
                else { hue = 60 * ((r - g) / delta + 4) }
                if hue < 0 { hue += 360 }
            }
            let idx = min(Int(hue / 30), 11)
            buckets[idx].rSum += r * sat
            buckets[idx].gSum += g * sat
            buckets[idx].bSum += b * sat
            buckets[idx].weight += sat
        }

        guard let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > 0 else { return nil }
        return (r: best.rSum / best.weight, g: best.gSum / best.weight, b: best.bSum / best.weight)
    }
}
```

### Step 4: 运行测试确认通过

Run: `swift test --filter DominantColorExtractorTests`
Expected: 全部 PASS

### Step 5: 提交

```bash
git add Sources/VanessaCore/DominantColorExtractor.swift Tests/VanessaCoreTests/DominantColorExtractorTests.swift
git commit -m "feat: 新增 DominantColorExtractor 封面主色提取"
```

---

## Task 2: 透传专辑色到歌词视图

**Files:**
- Modify: `Sources/VanessaApp/AppState.swift` — 新增 accentRGB，loadLyrics 中提取
- Modify: `Sources/VanessaApp/Views/KaraokeLineView.swift` — 接收 accentColor 参数
- Modify: `Sources/VanessaApp/Views/PlayingPanelView.swift` — 透传 accentColor
- Modify: `Sources/VanessaApp/Views/RootView.swift` — 透传 accentColor

### Step 1: AppState 新增 accentRGB

在 `AppState` 中新增：
```swift
/// 当前歌曲封面的主色调 RGB(0...1)；nil 时使用默认色。
private var accentRGB: (r: Double, g: Double, b: Double)?
```

在 `loadLyrics(for:)` 末尾、在 `do` 块的 `switch result` 之前添加颜色提取：
```swift
// 提取封面主色
if let data = state.artworkData {
    accentRGB = DominantColorExtractor.extract(from: data)
} else {
    accentRGB = nil
}
```

在 `handle(_ state:)` 中 `ui = .idle` 之前重置：
```swift
accentRGB = nil
```

在 `PlayingDisplay` 中新增字段：
```swift
public var accentR: Double
public var accentG: Double
public var accentB: Double
```

在 `refresh()` 中构造 PlayingDisplay 时填充：
```swift
let ar = accentRGB?.r ?? 229.0/255
let ag = accentRGB?.g ?? 199.0/255
let ab = accentRGB?.b ?? 192.0/255
// ... PlayingDisplay(..., accentR: ar, accentG: ag, accentB: ab)
```

### Step 2: KaraokeLineView 接收 accentColor

将 `Color.notchAccent` 引用替换为参数 `accentColor: Color`：
```swift
struct KaraokeLineView: View {
    let text: String
    let words: [Word]
    let position: LyricPosition
    var fontSize: CGFloat = 13
    var accentColor: Color = .notchAccent  // 默认值保持兼容
    // body 中把 Color.notchAccent 替换为 accentColor
}
```

### Step 3: PlayingPanelView 透传

在 `PlayingPanelView` 中新增 `var accentColor: Color = .notchAccent`，传给 KaraokeLineView。

### Step 4: RootView 透传

在 `.playing(let display)` 分支中从 display 构造 Color 并传入：
```swift
let accent = Color(red: display.accentR, green: display.accentG, blue: display.accentB)
PlayingPanelView(display: display, ..., accentColor: accent)
```

### Step 5: 运行全量测试

Run: `swift test`
Expected: 全部 PASS（现有 AppStateTests 不受影响，因为 PlayingDisplay 新字段有默认值传入路径）

### Step 6: 提交

```bash
git add -A
git commit -m "feat: 歌词文字颜色跟随封面主色变化"
```

---

## Task 3: MorphingNotchShape 变形形状

**Files:**
- Create: `Sources/VanessaApp/Views/MorphingNotchShape.swift`
- Create: `Tests/VanessaAppTests/MorphingNotchShapeTests.swift`

### Step 1: 编写测试

```swift
// Tests/VanessaAppTests/MorphingNotchShapeTests.swift
import XCTest
import CoreGraphics
@testable import VanessaApp

final class MorphingNotchShapeTests: XCTestCase {
    private let panelRect = CGRect(x: 0, y: 0, width: 260, height: 80)

    func test_progress0_isCenteredPill() {
        let shape = MorphingNotchShape(progress: 0)
        let bounds = shape.path(in: panelRect).boundingRect
        // 胶囊宽 140，居中于 260 → x ≈ 60
        XCTAssertEqual(bounds.width, 140, accuracy: 1)
        XCTAssertEqual(bounds.height, 22, accuracy: 1)
        XCTAssertEqual(bounds.midX, panelRect.midX, accuracy: 1)
    }

    func test_progress1_fillsRect() {
        let shape = MorphingNotchShape(progress: 1)
        let bounds = shape.path(in: panelRect).boundingRect
        XCTAssertEqual(bounds.width, panelRect.width, accuracy: 1)
        XCTAssertEqual(bounds.height, panelRect.height, accuracy: 1)
    }

    func test_progress05_isBetween() {
        let shape = MorphingNotchShape(progress: 0.5)
        let bounds = shape.path(in: panelRect).boundingRect
        XCTAssertGreaterThan(bounds.width, 140)
        XCTAssertLessThan(bounds.width, 260)
        XCTAssertGreaterThan(bounds.height, 22)
        XCTAssertLessThan(bounds.height, 80)
    }

    func test_animatableData_readWrite() {
        var shape = MorphingNotchShape(progress: 0.3)
        XCTAssertEqual(shape.animatableData, 0.3)
        shape.animatableData = 0.7
        XCTAssertEqual(shape.progress, 0.7)
    }
}
```

### Step 2: 运行测试确认失败

Run: `swift test --filter MorphingNotchShapeTests`
Expected: 编译失败

### Step 3: 实现 MorphingNotchShape

```swift
// Sources/VanessaApp/Views/MorphingNotchShape.swift
import SwiftUI

/// 可动画形状:在居中小胶囊(progress=0)与全尺寸刘海岛(progress=1)之间平滑插值。
struct MorphingNotchShape: Shape, Animatable {
    var progress: Double

    static let pillWidth: CGFloat = 140
    static let pillHeight: CGFloat = 22

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let t = CGFloat(min(max(progress, 0), 1))
        let w = lerp(Self.pillWidth, rect.width, t)
        let h = lerp(Self.pillHeight, rect.height, t)
        // 顶部圆角:胶囊全圆角 → 面板方角
        let topR = lerp(Self.pillHeight / 2, 0, t)
        // 底部圆角:胶囊全圆角 → 面板 18pt
        let botR = lerp(Self.pillHeight / 2, 18, t)
        let x = rect.midX - w / 2
        let y = rect.minY

        var p = Path()
        p.move(to: CGPoint(x: x + topR, y: y))
        p.addLine(to: CGPoint(x: x + w - topR, y: y))
        if topR > 0.5 {
            p.addQuadCurve(to: CGPoint(x: x + w, y: y + topR),
                           control: CGPoint(x: x + w, y: y))
        } else {
            p.addLine(to: CGPoint(x: x + w, y: y))
        }
        p.addLine(to: CGPoint(x: x + w, y: y + h - botR))
        p.addQuadCurve(to: CGPoint(x: x + w - botR, y: y + h),
                       control: CGPoint(x: x + w, y: y + h))
        p.addLine(to: CGPoint(x: x + botR, y: y + h))
        p.addQuadCurve(to: CGPoint(x: x, y: y + h - botR),
                       control: CGPoint(x: x, y: y + h))
        p.addLine(to: CGPoint(x: x, y: y + topR))
        if topR > 0.5 {
            p.addQuadCurve(to: CGPoint(x: x + topR, y: y),
                           control: CGPoint(x: x, y: y))
        } else {
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.closeSubpath()
        return p
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}
```

### Step 4: 运行测试确认通过

Run: `swift test --filter MorphingNotchShapeTests`
Expected: 全部 PASS

### Step 5: 提交

```bash
git add Sources/VanessaApp/Views/MorphingNotchShape.swift Tests/VanessaAppTests/MorphingNotchShapeTests.swift
git commit -m "feat: 新增 MorphingNotchShape 胶囊↔面板变形形状"
```

---

## Task 4: RootView 变形容器重构

**Files:**
- Modify: `Sources/VanessaApp/Views/RootView.swift`

### Step 1: 重构 RootView

将 switch 硬切改为统一变形容器。关键变更：

1. 新增 `@State morphProgress` 和 `displaySnapshot` 缓存
2. 用 `MorphingNotchShape` 做背景
3. 用 `onChange` 监听状态种类变化，驱动动画
4. 动画期间保留 PlayingDisplay 快照，收缩完成后清除

```swift
struct RootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: Settings
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    /// 播放 → 空闲收缩动画完成后的窗口缩小回调。
    var onShrinkComplete: (() -> Void)?

    @State private var morphProgress: Double = 0
    /// 动画收缩期间保留的播放快照(避免 .idle 后内容立即消失)。
    @State private var displaySnapshot: PlayingDisplay?

    var body: some View {
        ZStack(alignment: .top) {
            MorphingNotchShape(progress: morphProgress)
                .fill(.black)

            if let display = currentDisplay, morphProgress > 0 {
                let accent = Color(red: display.accentR, green: display.accentG, blue: display.accentB)
                PlayingPanelView(display: display,
                                 fontSize: CGFloat(settings.fontSize),
                                 width: CGFloat(settings.panelWidth),
                                 height: CGFloat(settings.panelHeight),
                                 accentColor: accent)
                    .opacity(morphProgress)
            }

            if morphProgress < 1 {
                idleContent.opacity(1 - morphProgress)
            }
        }
        .contentShape(MorphingNotchShape(progress: morphProgress))
        .contextMenu {
            Button("偏好设置") { onOpenSettings() }
            Button("退出") { onQuit() }
        }
        .onChange(of: stateKind) { newKind in
            if newKind == 2 {
                // → playing: 展开
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    morphProgress = 1
                }
            } else {
                // → idle/warning: 收缩
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    morphProgress = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    displaySnapshot = nil
                    onShrinkComplete?()
                }
            }
        }
        .onChange(of: playingDisplay) { display in
            if let display { displaySnapshot = display }
        }
        .onAppear {
            // 启动时已在播放则跳过动画
            if stateKind == 2 { morphProgress = 1 }
        }
    }

    private var stateKind: Int {
        switch appState.ui {
        case .idle: return 0
        case .warning: return 1
        case .playing: return 2
        }
    }

    private var playingDisplay: PlayingDisplay? {
        if case .playing(let d) = appState.ui { return d }
        return nil
    }

    private var currentDisplay: PlayingDisplay? {
        playingDisplay ?? displaySnapshot
    }

    @ViewBuilder private var idleContent: some View {
        switch appState.ui {
        case .warning:
            IdlePillView(isWarning: true, onTap: onOpenSettings)
        default:
            IdlePillView(isWarning: false, onTap: onOpenSettings)
        }
    }
}
```

### Step 2: 运行测试

Run: `swift test`
Expected: 全部 PASS

### Step 3: 提交

```bash
git add Sources/VanessaApp/Views/RootView.swift
git commit -m "feat: RootView 改为变形容器，支持形态动画过渡"
```

---

## Task 5: AppDelegate 窗口时序协调

**Files:**
- Modify: `Sources/VanessaApp/NotchWindowController.swift` — 新增 shrinkAfterDelay
- Modify: `Sources/VanessaApp/AppDelegate.swift` — 协调展开/收缩时序

### Step 1: NotchWindowController 新增延迟收缩

```swift
/// 延迟收缩窗口(供动画完成后调用)。
public func shrinkAfterDelay(_ size: CGSize, delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.contentSize = size
    }
}
```

### Step 2: AppDelegate.adjustWindow 改为协调时序

```swift
private func adjustWindow(for ui: AppUIState) {
    let kind: Int
    switch ui {
    case .idle:    kind = 0
    case .warning: kind = 1
    case .playing: kind = 2
    }
    guard kind != lastKind else { return }
    let prevKind = lastKind
    lastKind = kind

    if kind == 2 {
        // → playing: 立即扩大窗口，动画由 RootView 驱动
        windowController.contentSize = playingSize()
    } else if prevKind == 2 {
        // playing → idle/warning: 延迟收缩，等 RootView 动画完成
        windowController.shrinkAfterDelay(Self.idleSize, delay: 0.5)
    } else {
        windowController.contentSize = Self.idleSize
    }
}
```

### Step 3: AppDelegate 创建 RootView 时传入 onShrinkComplete（可选，如需更精确回调）

当前方案用固定 0.5s 延迟已足够。如果未来需要更精确的回调可以替换。

### Step 4: 运行全量测试

Run: `swift test`
Expected: 全部 PASS

### Step 5: 提交

```bash
git add Sources/VanessaApp/NotchWindowController.swift Sources/VanessaApp/AppDelegate.swift
git commit -m "feat: 协调窗口尺寸与变形动画时序"
```

---

## Task 6: 最终验证

- [ ] `swift test` 全部通过
- [ ] `swift build` 无警告
- [ ] 手动播放歌曲验证：歌词颜色跟随封面变化
- [ ] 手动播放/暂停验证：胶囊 ↔ 面板平滑变形
- [ ] 手动快速切歌验证：快速切换不卡顿
