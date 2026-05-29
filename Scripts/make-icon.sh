#!/usr/bin/env bash
# 生成 App 图标 Resources/AppIcon.icns(从 1024 主图缩放出全套 iconset)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/dist/appicon_1024.png"
ICONSET="$ROOT/dist/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

mkdir -p "$ROOT/dist" "$ROOT/Resources"

echo "==> 绘制 1024 主图"
swift "$ROOT/Scripts/draw-icon.swift" "$MASTER"

echo "==> 生成 iconset 各尺寸"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
gen() { sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

echo "==> 合成 icns"
iconutil -c icns "$ICONSET" -o "$ICNS"
echo "==> 完成:$ICNS"
