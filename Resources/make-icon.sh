#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PNG="$ROOT/icon-1024.png"
ICONSET="$ROOT/AppIcon.iconset"
OUT="$ROOT/AppIcon.icns"

if ! command -v magick >/dev/null 2>&1; then
  echo "需要 ImageMagick 才能生成图标；如果已有 AppIcon.icns，可以直接构建。" >&2
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

magick -size 1024x1024 gradient:'#3b9bff-#0a4fb8' \
  \( -size 1024x1024 xc:black -fill white -draw 'roundrectangle 56,56 968,968 220,220' \) \
  -alpha off -compose CopyOpacity -composite \
  -stroke 'rgba(255,255,255,0.28)' -strokewidth 5 -fill none -draw 'roundrectangle 72,72 952,952 204,204' \
  -stroke none -font '/System/Library/Fonts/Supplemental/Arial Bold.ttf' -fill white -pointsize 390 -gravity center -annotate +0+12 '>_' \
  "$PNG"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"
echo "wrote $OUT"
