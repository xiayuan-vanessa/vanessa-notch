# Vanessa-Notch 设计文档

- 日期:2026-05-29
- 状态:设计已对齐,待用户最终评审
- 平台:macOS 13 (Ventura)+,刘海机型为主,非刘海屏提供降级方案

## 1. 产品定义

Vanessa-Notch 是一个 macOS 菜单栏后台小工具(无 Dock 图标),专注做**一件事**:在刘海屏的刘海周围,实时显示网易云音乐当前播放歌曲的歌词,逐字卡拉OK高亮。

范围明确:
- 只支持**网易云音乐**作为音乐来源
- 只做**歌词显示**,不做播放控制、不做其他灵动岛功能(充电、AirDrop 等一律不做)

## 2. 技术选型

- **原生 Swift + SwiftUI + AppKit**。核心是"在刘海处精确叠加置顶透明窗口"+"读取系统 MediaRemote",强依赖 macOS 原生能力。
- 不用 Electron:对这两件核心事都不擅长,且重、耗内存。
- 菜单栏代理 App(`LSUIElement = true`,无 Dock 图标)。
- 通过 [`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter) 解决 macOS 15.4+ 对第三方读取系统"正在播放"的 entitlement 限制(无需关闭 SIP)。

## 3. 数据来源

### 3.1 正在播放(NowPlaying)
- 来源:MediaRemote(经 adapter)。
- 字段:歌名、歌手、专辑、封面、时长、当前进度(elapsed)、采样时刻、播放倍速、是否播放、来源 App 的 bundle id。
- 过滤:仅当来源 App 为网易云(`com.netease.163music`,以实际 bundle id 为准)时激活;其余一律视为空闲。

### 3.2 歌词
- 来源:网易云公开接口(非官方)。
- 流程:
  1. 用 `歌名 + 歌手` 调搜索接口,得到候选歌曲列表
  2. 用**时长容差 + 标题/歌手归一化**从候选中选最匹配的歌(`SongMatcher`)
  3. 用选中的**歌曲 ID** 拉取 **LRC + yrc(逐字)歌词**
  4. 按歌曲 ID 缓存(内存 + 磁盘)
- 置信度低时:宁可只显示"歌名 - 歌手",绝不显示错歌词。

### 3.3 进度同步
- 实时位置 = `elapsed + (当前时刻 − 采样时刻) × 倍速`。
- 以约 30fps 的 tick 驱动逐字高亮;暂停时停止推进。

## 4. 模块拆分(单一职责、可独立测试)

| 模块 | 职责 | 依赖 |
|------|------|------|
| `NowPlayingProvider`(协议)+ `MediaRemoteNowPlayingProvider` | 对外吐"正在播放"状态流 | adapter |
| `NeteaseLyricsRepository`(协议 + 实现) | 输入(歌名,歌手,时长)→ 统一歌词模型 | 下面三者 + 缓存 |
| `NeteaseAPIClient` | 封装搜索 / 歌词两个网易云接口 | URLSession |
| `SongMatcher`(纯函数) | 从搜索结果选最匹配歌曲 | 无 |
| `LyricsParser`(纯函数) | LRC + YRC → 统一歌词模型 | 无 |
| `PlaybackClock` | 由进度+倍速推算实时位置并 tick | 无 |
| `LyricSyncEngine`(纯函数) | 时间 →(当前行索引,当前字进度) | 无 |
| `NotchWindowController`(AppKit) | 刘海处置顶透明窗口的创建/定位/多屏/降级 | NSScreen |
| `AppState`(ObservableObject) | 编排所有模块,输出 UI 状态 | 以上全部 |
| SwiftUI 视图 | 播放面板 / 空闲胶囊 / 设置弹窗 | AppState |

### 数据模型(核心)
```
NowPlayingState { title, artist, album, artwork, duration, elapsed, sampledAt, rate, isPlaying, sourceBundleID }
Lyrics { lines: [LyricLine] }
LyricLine { startMs, endMs, text, words: [Word] }   // words 为空表示该行无逐字信息
Word { startMs, endMs, text }
```

## 5. 数据流

```
网易云播放
  → MediaRemote adapter
  → NowPlayingProvider 吐状态
  → AppState 检测到换歌
  → NeteaseLyricsRepository 拉歌词(搜索→选歌→歌词,带缓存)
  → 得到 Lyrics 模型
  → PlaybackClock 持续 tick 出实时位置 t
  → LyricSyncEngine 把 t 映射成(当前行, 当前字进度)
  → SwiftUI 渲染:单行逐字高亮 + 封面 + 装饰音频条
```

## 6. 运行状态

1. **播放网易云**:刘海下方黑色圆角面板 = 左侧封面 + 右侧装饰音频条 + 下方单行逐字歌词。
   - 无歌词/纯音乐:那一行显示 `♪ 纯音乐` 占位
   - 鼠标悬停:无变化(保持极简)
2. **暂停**:面板保留,歌词与音频条静止。
3. **空闲(没播放 / 来源不是网易云)**:收成刘海边的小胶囊;点击胶囊 → 设置弹窗。
   - 设置项:歌词字号、位置微调、开机启动、退出
   - adapter 不可用时,胶囊显示"警告态",设置里给出状态说明与授权指引

## 7. 关键决策与如实声明

- **音频跳动条是装饰动画**,非真实频谱。拿不到网易云音频采样,跳动条只按"是否在播放"做装饰动效,不反映真实声音。
- **无法上架 App Store**(非公开网易云接口 + 私有 MediaRemote)。分发方式:**notarized DMG 直接下载**,定位个人/开源使用。

## 8. 错误处理

- adapter 不可用/被系统拦:显示空闲胶囊"警告态" + 设置内状态说明,记录日志,不崩溃。
- 歌词接口失败/限流:退避重试;失败降级显示"歌名 - 歌手";短期缓存失败结果避免狂刷。
- 选歌置信度低:显示"歌名 - 歌手"而非错歌词。
- 断网:显示"歌名 - 歌手",联网后重试。
- 刘海几何拿不到(外接非刘海屏):降级为该屏顶部居中浮动圆角面板,或隐藏(可设置)。

## 9. 测试策略

- 纯函数单测(XCTest):
  - `LyricsParser`:空、畸形、offset 标签、多空格、无 yrc 仅 lrc
  - `SongMatcher`:时长容差、标题/歌手归一化、feat. 处理、无匹配
  - `LyricSyncEngine`:首行之前、行间间隙、末行、字边界
  - `PlaybackClock`:倍速、暂停、时间漂移
- `NeteaseAPIClient`:录制 fixture + URLProtocol 打桩,**测试不打真实网络**。
- `AppState`:注入假的 `NowPlayingProvider` 驱动,验证状态切换。
- 真机 QA(无法自动化部分):换歌、拖动进度、暂停、纯音乐、断网、外接屏、macOS 15.4+ 实测。

## 10. 项目信息

- 应用名:**Vanessa-Notch**
- 仓库根:`/Users/vanessa/macos-notch-lyrics`
- 分发:notarized DMG

## 11. 明确不做(YAGNI)

- 播放控制(上一首/下一首/暂停按钮)
- 多音乐源(Apple Music / Spotify)
- 真实音频频谱
- 真实灵动岛多功能(充电、AirDrop、计时器、剪贴板等)
- 悬停展开多行歌词
