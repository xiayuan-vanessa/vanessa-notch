# 专辑色主题 + 灵动岛变形动画 设计文档

## 概述

为 Vanessa-Notch 新增两个独立功能：
1. **专辑色主题**：从封面图提取主色调，替代歌词文字的固定强调色
2. **灵动岛变形动画**：空闲胶囊 ↔ 播放面板切换时，形状连续变形过渡

两个功能互相独立，无依赖关系。

---

## 功能 1：专辑色主题

### 目标

歌词文字颜色跟随当前歌曲封面的主色调变化，其他 UI 元素（均衡器条、空闲胶囊）保持固定色不变。

### 作用范围

仅 `KaraokeLineView` 中的歌词文字（已唱高亮色 + 未唱半透明色）。

### 架构

```
artworkData (Data)
    → DominantColorExtractor.extract(from:) → Color?
    → AppState.accentColor (fallback: Color.notchAccent)
    → PlayingDisplay.accentColor → KaraokeLineView
```

### 组件设计

#### DominantColorExtractor

位置：`Sources/VanessaCore/DominantColorExtractor.swift`

纯函数，无状态，无副作用。

```
public enum DominantColorExtractor {
    static func extract(from imageData: Data) -> (r: Double, g: Double, b: Double)?
}
```

算法：
1. `Data` → `CGImage`（通过 `NSImage` 或 `CGImageSource`）
2. 缩采样到 32×32（避免大图遍历开销）
3. 遍历像素，转换为 HSB 色彩空间
4. 过滤条件：亮度 >= 0.3，饱和度 >= 0.15（排除黑色/灰色系）
5. 按饱和度加权取最频繁的色相区间（将 0-360° 分为 12 个桶）
6. 返回该桶内像素的平均 RGB

返回 RGB 元组而非 `Color`，因为 `VanessaCore` 不依赖 SwiftUI。

失败情况（返回 nil）：
- 图片数据无法解码
- 所有像素都被过滤掉（纯黑/纯灰封面）

#### AppState 变更

新增属性：
```swift
@Published public private(set) var accentColor: Color = .notchAccent
```

在 `loadLyrics(for:)` 中，换歌时同步提取颜色：
```swift
if let rgb = DominantColorExtractor.extract(from: artworkData) {
    accentColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
} else {
    accentColor = .notchAccent
}
```

注意：颜色提取在 `loadLyrics` 中进行（非每次 diff），仅换歌时触发一次。

#### PlayingDisplay 变更

新增字段：
```swift
public var accentColor: Color
```

在 `AppState.refresh()` 中填充。

#### KaraokeLineView 变更

新增参数 `accentColor: Color`，替代所有 `Color.notchAccent` 引用。

### 边界条件

- 无封面图 → 使用默认 `#E5C7C0`
- 纯黑/纯白封面 → 所有像素被过滤，返回 nil → 使用默认色
- 封面图解码失败 → 返回 nil → 使用默认色
- 歌曲切换时颜色即时变化，不做渐变过渡（简单直接）

---

## 功能 2：灵动岛变形动画

### 目标

空闲胶囊 ↔ 播放面板切换时，形状平滑膨胀/收缩过渡，类似 iPhone 灵动岛效果。

### 现状问题

当前切换流程：
1. `AppState.ui` 变化 → `AppDelegate.adjustWindow` 立即改变 `contentSize`
2. `RootView` 通过 `switch` 硬切 `IdlePillView` / `PlayingPanelView`
3. 窗口尺寸突变，视图瞬切，无过渡效果

### 动画策略

核心思路：窗口提前扩大/延迟收缩，SwiftUI 内部做连续形状变形。

#### idle → playing 时序

```
T0: AppState.ui 变为 .playing
T0: NSWindow 立即扩大到 playingSize（内容尚在胶囊态）
T0: SwiftUI withAnimation 触发 morphProgress 0→1
T0~T400ms: 形状从胶囊连续变形为圆角矩形，内容淡入
```

#### playing → idle 时序

```
T0: AppState.ui 变为 .idle
T0: SwiftUI withAnimation 触发 morphProgress 1→0
T0~T400ms: 形状从圆角矩形收缩为胶囊，内容淡出
T400ms: 动画完成回调 → NSWindow 缩小到 idleSize
```

### 组件设计

#### MorphingNotchShape

位置：`Sources/VanessaApp/Views/MorphingNotchShape.swift`

可动画的自定义 Shape，在胶囊 ↔ NotchIslandShape 之间插值。

```swift
struct MorphingNotchShape: Shape, Animatable {
    var progress: Double  // 0 = 胶囊, 1 = 圆角矩形岛
    var animatableData: Double { get/set → progress }

    func path(in rect: CGRect) -> Path {
        // progress=0: 居中的小胶囊（宽 140, 高 22）
        // progress=1: 撑满 rect 的 NotchIslandShape
        // 中间值: 宽高和圆角线性插值
    }
}
```

关键插值参数：
- 宽度：`lerp(140, rect.width, progress)`
- 高度：`lerp(22, rect.height, progress)`
- 圆角：`lerp(11, 18, progress)`（胶囊用半高圆角，面板用 18pt）
- 位置：始终水平居中、顶部对齐

#### RootView 变更

不再用 `switch` 硬切视图，改为统一的变形容器：

```swift
var body: some View {
    ZStack(alignment: .top) {
        MorphingNotchShape(progress: morphProgress)
            .fill(.black)

        // 播放内容（progress > 0 时显示）
        if isPlaying {
            PlayingPanelView(...)
                .opacity(morphProgress)
        }

        // 空闲内容（progress < 1 时显示）
        if !isPlaying {
            IdlePillView(...)
                .opacity(1 - morphProgress)
        }
    }
}
```

使用 `@State private var morphProgress: Double = 0`，在状态变化时用 `withAnimation` 驱动。

#### AppDelegate / NotchWindowController 变更

`NotchWindowController` 新增方法：

```swift
func resizeAnimated(to size: CGSize, completion: (() -> Void)? = nil)
```

`AppDelegate.adjustWindow` 变更逻辑：
- idle → playing：先 resize 到 playingSize，再通知 RootView 开始动画
- playing → idle：先通知 RootView 开始收缩动画，延迟 ~450ms 后 resize 到 idleSize

通信方式：通过 `AppState` 上的一个 `@Published var displayMode: DisplayMode`（`.idle` / `.playing`），RootView 观察并驱动动画。窗口尺寸调整仍由 AppDelegate 控制。

### 动画参数

```swift
.spring(response: 0.45, dampingFraction: 0.82)
```

- response 0.45s：足够看到变形过程，不拖沓
- dampingFraction 0.82：轻微弹性但不过度

### 命中测试

动画期间窗口扩大但内容未撑满时，透明区域不应拦截鼠标事件：
- 方案：MorphingNotchShape 作为 `contentShape`，仅形状区域可交互

### 边界条件

- 快速切换（播放→暂停→播放 间隔 < 400ms）：新动画打断旧动画，SwiftUI 自动处理插值衔接
- 屏幕参数变化（外接显示器）：动画中途触发 reposition 不影响，窗口位置重算即可
- 应用启动时如果已在播放：跳过动画，直接以 progress=1 显示

---

## 测试策略

### 专辑色主题

- `DominantColorExtractor` 单元测试：
  - 纯色图片 → 返回该颜色
  - 纯黑图片 → 返回 nil
  - 无效数据 → 返回 nil
  - 混合色图片 → 返回最饱和的主色

### 灵动岛变形动画

- `MorphingNotchShape` 单元测试：
  - progress=0 → 路径为居中胶囊
  - progress=1 → 路径为全尺寸圆角矩形
  - progress=0.5 → 中间尺寸
- 视觉验证：需手动播放歌曲观察过渡效果

---

## 不做的事

- 不对均衡器条、空闲胶囊应用专辑色
- 不做颜色渐变过渡（换歌时颜色即时切换）
- 不做内容元素的 matchedGeometryEffect（封面/均衡器不做位置连续动画，仅整体淡入淡出）
- 不改变现有的窗口层级和 collectionBehavior
