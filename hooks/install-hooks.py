#!/usr/bin/env python3
"""~/.claude/settings.json 에 Clawd Pet 훅과 statusLine을 연결하거나(기본) 떼어 낸다(--remove).

이 저장소를 받은 위치를 기준으로 경로를 넣기 때문에, 누가 어디에 받아도 그 사람 맥에 맞게 설정된다.
이미 있는 다른 설정은 그대로 두고, 바꾸기 전 원본은 settings.json.bak-clawd 로 남긴다.
"""
import json
import os
import sys

remove = "--remove" in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith("--")]
root = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(__file__), ".."))
path = os.path.expanduser("~/.claude/settings.json")

settings = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
    with open(path + ".bak-clawd", "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
elif remove:
    print("Claude Code 설정 파일이 없어서 떼어 낼 것이 없어요.")
    sys.exit(0)


def is_ours(entry):
    return entry.get("command", "").endswith("clawd-hook.sh")


hooks = settings.setdefault("hooks", {})
events = [("UserPromptSubmit", None), ("PreToolUse", "*"), ("PostToolUse", "*"),
          ("Notification", None), ("Stop", None), ("SessionEnd", None)]

if remove:
    for event in list(hooks):
        groups = []
        for group in hooks[event]:
            group["hooks"] = [entry for entry in group.get("hooks", []) if not is_ours(entry)]
            if group["hooks"]:
                groups.append(group)
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]
    if not hooks:
        del settings["hooks"]
    if (settings.get("statusLine") or {}).get("command", "").endswith("clawd-statusline.sh"):
        del settings["statusLine"]
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    hook = os.path.join(root, "hooks", "clawd-hook.sh")
    for event, matcher in events:
        groups = hooks.setdefault(event, [])
        found = False
        for group in groups:
            for entry in group.get("hooks", []):
                if is_ours(entry):
                    entry["command"] = hook   # 예전 위치를 가리키고 있으면 지금 위치로
                    found = True
        if not found:
            group = {"hooks": [{"type": "command", "command": hook, "timeout": 5}]}
            if matcher:
                group["matcher"] = matcher
            groups.append(group)

    status_line = os.path.join(root, "hooks", "clawd-statusline.sh")
    current = (settings.get("statusLine") or {}).get("command", "")
    if not current or current.endswith("clawd-statusline.sh"):
        settings["statusLine"] = {"type": "command", "command": status_line}
    else:
        print(f"이미 다른 statusLine이 있어서 그대로 뒀어요: {current}")

with open(path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"Claude Code 연결을 {'풀었어요' if remove else '마쳤어요'}: {path}")
