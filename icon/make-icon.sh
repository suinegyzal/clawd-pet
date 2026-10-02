#!/bin/bash
# 앱 아이콘(icon/AppIcon.icns)을 Sources/ClawdSprite.swift 의 픽셀 Clawd로 다시 만든다. 스프라이트를 고쳤을 때만 실행하면 된다.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
xcrun swiftc -parse-as-library Sources/ClawdSprite.swift icon/make-icon.swift -o "$tmp/make-icon"
set="$tmp/AppIcon.iconset"; mkdir -p "$set"
"$tmp/make-icon" "$tmp"
for s in 16 32 128 256 512; do
  cp "$tmp/icon_$s.png" "$set/icon_${s}x${s}.png"
  cp "$tmp/icon_$((s*2)).png" "$set/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$set" -o icon/AppIcon.icns
cp "$tmp/icon_256.png" icon/AppIcon-preview.png
rm -rf "$tmp"
echo "아이콘 생성: icon/AppIcon.icns"
