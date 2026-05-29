#!/usr/bin/env bash
# 组装 Vanessa-Notch.app:编译 release -> 拼 bundle -> 写 Info.plist -> 拷 adapter 资源。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Vanessa-Notch.app"
BIN_NAME="vanessa-notch"

echo "==> 编译 release"
swift build -c release --product "$BIN_NAME"
BIN_PATH="$(swift build -c release --product "$BIN_NAME" --show-bin-path)/$BIN_NAME"

echo "==> 重建 bundle 目录"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 拷可执行文件与 Info.plist"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> 拷 App 图标(若存在)"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "   [警告] 未找到 Resources/AppIcon.icns —— 先运行 ./Scripts/make-icon.sh"
fi

echo "==> 拷 adapter 资源(若存在)"
if [ -f "$ROOT/vendor/mediaremote-adapter.pl" ]; then
  cp "$ROOT/vendor/mediaremote-adapter.pl" "$APP/Contents/Resources/"
else
  echo "   [警告] 未找到 vendor/mediaremote-adapter.pl —— App 将以警告态运行"
fi
if [ -d "$ROOT/vendor/MediaRemoteAdapter.framework" ]; then
  cp -R "$ROOT/vendor/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"
else
  echo "   [警告] 未找到 vendor/MediaRemoteAdapter.framework —— App 将以警告态运行"
fi

echo "==> 完成:$APP"
