#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '.work/\n' >.gitignore
mkdir -p inbox
printf 'a\n' >inbox/one.txt
printf 'b\n' >inbox/two.txt
printf 'c\n' >inbox/three.txt
git add -A
git commit -q -m "chore: starting point"
mkdir -p .work
printf '*\n' >.work/.gitignore
cp -R "$here/fixtures/handoffs" .work/handoffs
name=20261124T100000Z-handoff-queue-watch.md
since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sed "/^- \[loop\] /s/since [^ ]*/since $since/" "$here/fixtures/handoffs/$name" >".work/handoffs/$name"

python3 - ".work/handoffs/$name" >.work/resume-paste.json <<'PY'
import json
import sys
from pathlib import Path

handoff = Path(sys.argv[1]).resolve(strict=True)
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "initialUserMessage": f"Read @{handoff}, confirm its Original goal still governs the remaining actions, then continue them.",
}}))
PY
