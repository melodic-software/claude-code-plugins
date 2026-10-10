#!/usr/bin/env bash
# effort-probe.sh <dir>: the subagent effort fixture under <dir>/.claude/.
#   agents/effort-probe.md           pins `effort: low`, preloads print-effort
#   agents/effort-probe-unpinned.md  no effort key, preloads print-effort
#   skills/print-effort/SKILL.md     one Bash call: echo effort=${CLAUDE_EFFORT}
#   hooks/log-effort.py              appends each hook payload's effort.level to
#                                    <dir>/effort.log, a reading independent of
#                                    the skill's substitution; the case's
#                                    settings.json registers it
set -euo pipefail
d="$1"
mkdir -p "$d/.claude/agents" "$d/.claude/skills/print-effort" "$d/.claude/hooks"

agent() {
  {
    echo "---"
    echo "name: $1"
    echo "description: Behavior-probe subagent that prints its own effort level once."
    echo "tools: Bash"
    [[ -z "$2" ]] || echo "effort: $2"
    echo "skills:"
    echo "  - print-effort"
    echo "---"
    echo
    echo "Follow the preloaded print-effort skill exactly: make its one Bash call once,"
    echo "then report the tool result verbatim. Make no other tool call."
  } >"$d/.claude/agents/$1.md"
}
agent effort-probe low
agent effort-probe-unpinned ""

cat >"$d/.claude/skills/print-effort/SKILL.md" <<'EOF'
---
name: print-effort
description: Print this agent's effort level with one Bash call.
---

Run this Bash command exactly once, character for character: `echo effort=${CLAUDE_EFFORT}`

Then report the tool result verbatim.
EOF

cat >"$d/.claude/hooks/log-effort.py" <<'EOF'
import json
import os
import sys
from pathlib import Path

payload = json.load(sys.stdin)
effort = payload.get("effort") if isinstance(payload.get("effort"), dict) else {}
fields = {
    "event": payload.get("hook_event_name"),
    "agent_type": payload.get("agent_type") or "main",
    "tool": payload.get("tool_name") or "-",
    "effort": effort.get("level") or "unset",
    "env": os.environ.get("CLAUDE_EFFORT") or "unset",
}
log = Path(__file__).resolve().parents[2] / "effort.log"
with log.open("a", encoding="utf-8") as fh:
    fh.write(" ".join(f"{k}={v}" for k, v in fields.items()) + "\n")
EOF
