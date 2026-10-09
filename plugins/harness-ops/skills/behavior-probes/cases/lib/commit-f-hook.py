"""PreToolUse hook: rewrite a multi-line `git commit -m <msg>` to `git commit -F -` fed by a heredoc.

It returns updatedInput and no permissionDecision, so the call stays with the permission layer.
With --mark, the rewrite ends with a line echoing PROBE_REWRITE_APPLIED, so the tool result shows
which command ran. Without it the rewrite is the bare heredoc commit; a default-mode case then
tells the two forms apart with an allow rule that matches only the rewrite. Text after the
heredoc start on the same line is denied in default mode before any rule is read.
"""

import json
import shlex
import sys

event = json.load(sys.stdin)
tool_input = event.get("tool_input") or {}
try:
    words = shlex.split(tool_input.get("command", ""))
except ValueError:
    words = []
if (
    event.get("tool_name") == "Bash"
    and len(words) == 4
    and words[:3] == ["git", "commit", "-m"]
    and "\n" in words[3]
    and "PROBE_MSG" not in words[3]
):
    command = f"git commit -F - <<'PROBE_MSG'\n{words[3]}\nPROBE_MSG"
    if "--mark" in sys.argv[1:]:
        command += "\necho PROBE_REWRITE_APPLIED"
    output = {
        "hookEventName": "PreToolUse",
        "updatedInput": {**tool_input, "command": command},
    }
    print(json.dumps({"hookSpecificOutput": output}))
