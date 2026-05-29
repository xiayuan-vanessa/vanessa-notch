#!/usr/bin/env bash
# 把 dist/Vanessa-Notch.app 打包成可拖拽安装的 DMG。
# 无 Developer ID 时做 ad-hoc 签名(本地/个人可用;正式分发需 Developer ID + 公证,见 docs/DISTRIBUTION.md)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Vanessa-Notch.app"
DMG="$ROOT/dist/Vanessa-Notch.dmg"
VOL="Vanessa-Notch"

[ -d "$APP" ] || { echo "未找到 $APP,请先运行 ./Scripts/build-app.sh"; exit 1; }

echo "==> ad-hoc 签名(含内嵌 framework)"
codesign --force --deep --sign - "$APP" || echo "   [警告] 签名失败,继续打包(DMG 仍可用,首次打开需右键)"

echo "==> 组装 DMG 暂存目录(含 Applications 快捷方式)"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> 生成 DMG"
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> 完成:$DMG"
ls -lh "$DMG" | awk '{print "    大小:", $5}'
