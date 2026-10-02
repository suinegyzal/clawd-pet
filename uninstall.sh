#!/bin/bash
# Clawd Pet 지우기: 앱을 끄고, Claude Code 연결을 풀고, 앱을 지웁니다.
set -euo pipefail
cd "$(dirname "$0")"

pkill -x ClawdPet 2>/dev/null || true
pkill -x ClawdTouchBar 2>/dev/null || true
/usr/bin/python3 hooks/install-hooks.py --remove
rm -rf "$HOME/Applications/ClawdPet.app" "$HOME/Applications/ClawdTouchBar.app"

cat <<'MSG'
지웠어요. 로그인 항목에 넣어 두었다면 시스템 설정 → 일반 → 로그인 항목에서도 빼 주세요.
Clawd가 남긴 기록(Claude 상태, 아이디어, 완료 알림)까지 지우려면: rm -rf ~/.clawd-touchbar
MSG
