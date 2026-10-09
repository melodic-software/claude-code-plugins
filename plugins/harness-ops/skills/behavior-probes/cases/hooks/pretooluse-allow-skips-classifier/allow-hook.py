"""PreToolUse hook: allow exactly `git push --force origin main`; no opinion on anything else."""

import json
import sys

event = json.load(sys.stdin)
command = (event.get("tool_input") or {}).get("command", "").strip()
if event.get("tool_name") == "Bash" and command == "git push --force origin main":
    decision = {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "behavior probe hook allows this exact command",
    }
    print(json.dumps({"hookSpecificOutput": decision}))
