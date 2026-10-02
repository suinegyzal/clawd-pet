#!/bin/bash
# Clawd Pet 빌드: build/ClawdPet.app 을 만든다.
#   ./build.sh            내 맥 아키텍처만 (빠름, 개발용)
#   ./build.sh universal  Intel + Apple Silicon 둘 다 (배포용)
#   VERSION=1.2.0 ./build.sh universal   버전 표기
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift 컴파일러가 없습니다. 먼저 'xcode-select --install' 로 Command Line Tools를 설치하세요." >&2
  exit 1
fi

APP="build/ClawdPet.app"
VERSION="${VERSION:-1.0}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/hooks"

compile() {  # $1 = arch, $2 = 출력 파일
  xcrun swiftc -O -parse-as-library -target "$1-apple-macos12.0" Sources/*.swift -o "$2"
}

if [ "${1:-}" = "universal" ]; then
  compile arm64 build/ClawdPet-arm64
  compile x86_64 build/ClawdPet-x86_64
  lipo -create build/ClawdPet-arm64 build/ClawdPet-x86_64 -output "$APP/Contents/MacOS/ClawdPet"
  rm -f build/ClawdPet-arm64 build/ClawdPet-x86_64
else
  compile "$(uname -m)" "$APP/Contents/MacOS/ClawdPet"
fi

# 앱이 첫 실행 때 ~/.clawd-touchbar/bin 으로 복사해 Claude Code에 연결하는 훅 스크립트
cp hooks/clawd-hook.sh hooks/clawd-statusline.sh "$APP/Contents/Resources/hooks/"
chmod +x "$APP/Contents/Resources/hooks/"*.sh
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clawd Pet</string>
  <key>CFBundleDisplayName</key><string>Clawd Pet</string>
  <key>CFBundleIdentifier</key><string>com.local.ClawdTouchBar</string>
  <key>CFBundleExecutable</key><string>ClawdPet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "빌드 완료: $APP (버전 $VERSION)"
