#!/bin/bash
# Clawd Pet 설치. 처음 받았을 때, 그리고 업데이트를 받은 뒤에 실행하세요.
#   1) 앱을 빌드해서 ~/Applications 에 넣고
#   2) 내 Claude Code(~/.claude/settings.json)에 훅과 상태줄을 연결하고
#   3) 앱을 (다시) 띄웁니다.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "앱을 빌드하려면 Xcode Command Line Tools가 필요해요. 설치 창을 띄울게요."
  xcode-select --install >/dev/null 2>&1 || true
  echo "설치 창에서 '설치'를 누르고, 끝나면 ./install.sh 를 다시 실행해 주세요."
  exit 1
fi

./build.sh
chmod +x hooks/*.sh
/usr/bin/python3 hooks/install-hooks.py "$(pwd)"

APP="$HOME/Applications/ClawdPet.app"
mkdir -p "$HOME/Applications"
pkill -x ClawdPet 2>/dev/null || true
pkill -x ClawdTouchBar 2>/dev/null || true   # 예전 이름
rm -rf "$HOME/Applications/ClawdTouchBar.app"
rm -rf "$APP"
cp -R build/ClawdPet.app "$APP"
open "$APP"

cat <<'MSG'

✅ 설치 완료!
- 화면 맨 위 메뉴 막대에 Clawd가 나타나요. Touch Bar가 있으면 Touch Bar에도 나와요.
- Claude Code 세션은 새로 시작해야 Clawd와 연동돼요.
- 로그인할 때 자동으로 켜려면: 시스템 설정 → 일반 → 로그인 항목 → + → 홈 폴더의 응용 프로그램 → ClawdPet
MSG
