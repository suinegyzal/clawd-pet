#!/bin/sh
# Claude Code statusLine → Clawd Pet.
# 입력(JSON: 모델, 컨텍스트, 사용량 한도)을 ~/.clawd-touchbar/statusline.json 에 저장해 두면
# 앱이 읽어서 Touch Bar에 보여 준다. 터미널 상태줄에는 모델 이름을 찍는다.
dir="$HOME/.clawd-touchbar"
mkdir -p "$dir" 2>/dev/null
input=$(cat)
tmp="$dir/.statusline.$$"
printf '%s' "$input" > "$tmp" 2>/dev/null && mv "$tmp" "$dir/statusline.json" 2>/dev/null
model=$(printf '%s' "$input" | sed -n 's/.*"display_name" *: *"\([^"]*\)".*/\1/p' | head -n 1)
printf '%s\n' "${model:-Claude}"
