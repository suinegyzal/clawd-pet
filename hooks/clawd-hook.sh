#!/bin/sh
# Claude Code 훅 → Clawd Pet.
# 훅 입력(JSON)을 ~/.clawd-touchbar/events 에 파일로 떨궈 두면 앱이 읽어 간다.
# 앱이 꺼져 있으면 아무것도 하지 않고, 어떤 경우에도 Claude Code를 막지 않는다.
pgrep -xq ClawdPet || { cat >/dev/null; exit 0; }
dir="$HOME/.clawd-touchbar/events"
mkdir -p "$dir" 2>/dev/null
json=$(cat)

# 이 세션이 어느 앱(Terminal, Claude 데스크톱, VS Code…)에서 돌고 있는지: 부모 프로세스를 거슬러 올라가 .app 안의 실행 파일을 찾는다.
# 완료 말풍선을 톡 치면 Clawd가 그 앱을 앞으로 가져온다.
app=""
pid=$PPID
while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
  exe=$(ps -o comm= -p "$pid" 2>/dev/null)
  case "$exe" in *.app/*) app="$exe" ;; esac
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
done
if [ -n "$app" ]; then
  esc=$(printf '%s' "$app" | sed 's/[\\"|&]/\\&/g')
  json=$(printf '%s' "$json" | sed '$ s|}[[:space:]]*$|,"clawd_app":"'"$esc"'"}|')
fi

tmp="$dir/.tmp.$$"
printf '%s' "$json" > "$tmp" 2>/dev/null && mv "$tmp" "$dir/$$.json" 2>/dev/null
exit 0
