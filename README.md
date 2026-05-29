# Vanessa-Notch

在 macOS 刘海处实时显示**网易云音乐**当前歌曲的逐字歌词。

启动后没有 Dock 图标，只在菜单栏右侧驻留；用网易云播放歌曲时，刘海下方会出现黑色岛形面板，显示封面、音频跳动条与逐字（卡拉 OK）歌词。

## 功能特性

- 🎵 自动读取系统「正在播放」信息，无需登录网易云
- 🎤 逐字高亮歌词（卡拉 OK 效果），支持原文 + 译文
- 🪟 贴合刘海的岛形面板；非刘海机型在屏幕顶部居中显示
- 🍫 菜单栏常驻，无 Dock 图标；左键打开设置，右键快捷菜单
- ⚙️ 可调歌词字号、面板宽高、开机启动等
- 💾 歌词本地缓存，减少重复请求
- 🎚️ 冷门歌曲降级显示「歌名 - 歌手」，纯音乐显示「♪ 纯音乐」

## 环境要求

- **Apple Silicon Mac（M 系列）**——发布的 DMG 仅含 arm64
- **macOS 13 (Ventura)** 及以上，刘海机型体验最佳
- 需安装并使用**网易云音乐**
- 需要联网获取歌词

## 安装（使用 DMG）

详见 [docs/INSTALL.md](docs/INSTALL.md)。简要步骤：

1. 双击 `Vanessa-Notch.dmg`，把图标拖入「应用程序」
2. 首次打开若被拦截（未公证），右键点 App →「打开」放行一次；或执行：
   ```bash
   xattr -dr com.apple.quarantine /Applications/Vanessa-Notch.app
   ```

## 从源码构建

需要安装 Xcode 命令行工具（Swift 5.9+）。

```bash
# 运行开发版本
swift run vanessa-notch

# 运行测试
swift test

# 打包 .app（输出到 dist/）
./Scripts/build-app.sh
```

## 项目结构

基于 Swift Package Manager，分层组织：

| 模块 | 职责 |
|------|------|
| `VanessaCore` | 核心逻辑：歌词解析、同步引擎、播放时钟、歌曲匹配 |
| `VanessaNetease` | 网易云歌词获取、缓存与仓库层 |
| `VanessaApp` | 应用层：刘海窗口、状态栏、设置与 SwiftUI 视图 |
| `vanessa-notch` | 可执行入口 |

各模块均配有单元测试（`Tests/`）。

## 分发

因使用网易云非公开接口 + 系统私有 MediaRemote，**无法上架 App Store**，采用 notarized DMG 直接下载分发。完整流程见 [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)。

## 说明与免责

- 音频跳动条为装饰动效，不代表真实频谱。
- 本工具使用网易云**非公开接口**与系统**私有接口**，仅供个人 / 开源学习使用。
- macOS 15.4+ 首次可能需在「系统设置 → 隐私与安全性」授权读取「正在播放」信息。
