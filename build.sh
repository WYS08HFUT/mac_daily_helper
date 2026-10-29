#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DailyHelp"
APP="$ROOT/build/$APP_NAME.app"
HTML_SOURCE="${HTML_SOURCE:-$ROOT/web/index.html}"
ARCH="$(uname -m)"

command -v xcrun >/dev/null 2>&1 || { echo "找不到 xcrun，请先安装 Command Line Tools：xcode-select --install" >&2; exit 1; }
xcrun --sdk macosx --find swiftc >/dev/null 2>&1 || { echo "找不到 swiftc，请先安装 Command Line Tools：xcode-select --install" >&2; exit 1; }
[ -f "$HTML_SOURCE" ] || { echo "找不到页面源文件：$HTML_SOURCE" >&2; exit 1; }
[ -f "$ROOT/Resources/Info.plist" ] || { echo "缺少 Resources/Info.plist" >&2; exit 1; }

if [ ! -f "$ROOT/Resources/AppIcon.icns" ] || [ "$ROOT/Resources/icon-1024.png" -nt "$ROOT/Resources/AppIcon.icns" ]; then
  "$ROOT/Resources/make-icon.sh"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

xcrun --sdk macosx swiftc \
  -O \
  -swift-version 5 \
  -target "${ARCH}-apple-macosx13.0" \
  -framework Cocoa \
  -framework WebKit \
  "$ROOT/Sources/main.swift" \
  -o "$APP/Contents/MacOS/$APP_NAME"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$HTML_SOURCE" "$APP/Contents/Resources/web/index.html"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

echo "Built: $APP"
echo "Open:  open \"$APP\""
