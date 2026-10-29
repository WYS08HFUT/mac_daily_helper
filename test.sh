#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DailyHelp"
APP="$ROOT/build/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"
BUNDLE_ID="local.dailyhelp.app"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[ -x "$ROOT/build.sh" ] || fail "build.sh 不存在或不可执行"
"$ROOT/build.sh"

[ -x "$BIN" ] || fail "缺少可执行文件 $BIN"
[ -f "$APP/Contents/Info.plist" ] || fail "缺少 Info.plist"
[ -f "$APP/Contents/Resources/web/index.html" ] || fail "缺少打包后的页面"
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || fail "缺少 AppIcon.icns"
pass "bundle 结构"

plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail "Info.plist 格式错误"
[ "$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")" = "$BUNDLE_ID" ] || fail "CFBundleIdentifier 不正确"
[ "$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")" = "$APP_NAME" ] || fail "CFBundleExecutable 不正确"
plutil -extract LSMinimumSystemVersion raw -o - "$APP/Contents/Info.plist" >/dev/null || fail "缺少 LSMinimumSystemVersion"
pass "Info.plist"

file "$BIN" | grep -q 'Mach-O' || fail "可执行文件不是 Mach-O"
grep -q 'id="command-list"' "$APP/Contents/Resources/web/index.html" || fail "页面缺少命令列表"
grep -q 'const COMMANDS' "$APP/Contents/Resources/web/index.html" || fail "页面缺少命令数据"
pass "可执行文件与页面"

codesign --verify --deep --strict "$APP" || fail "代码签名校验失败"
pass "ad-hoc 签名"

OUT="$(mktemp /tmp/dailyhelp-smoke.XXXXXX)"
"$BIN" --smoke-test >"$OUT" 2>&1 &
PID=$!
( sleep 25; kill -TERM "$PID" 2>/dev/null ) &
WATCH=$!
set +e
wait "$PID"
STATUS=$?
set -e
kill "$WATCH" 2>/dev/null || true
if [ "$STATUS" -ne 0 ] || ! grep -q 'SMOKE_OK rows=26 storage=ok clipboard=ok' "$OUT"; then
  echo "--- smoke output ---" >&2
  cat "$OUT" >&2
  rm -f "$OUT"
  fail "烟测未通过（exit $STATUS）"
fi
rm -f "$OUT"
pass "烟测：26 条命令、localStorage、剪贴板"

echo
echo "全部通过：$APP"
