#!/usr/bin/env bash
# instructions-probe.sh <dir>: after hub-layout.sh <dir>, the instruction-file fixture.
#   repos/github.com/acme/hub/CLAUDE.md       loads at session start, so the hook log
#                                             is never empty when the hook fires
#   repos/github.com/acme/hub/docs/CLAUDE.md  nested under the start directory
#   repos/github.com/acme/hub/docs/guide.md   the file whose Read loads it
#   repos/github.com/acme/target/CLAUDE.md    in the sibling repository
#   instructions-log.py    the case's settings register it for InstructionsLoaded
#                          (appends "loaded <file_path>") and PostToolUse on Read
#                          (appends "read <file_path>", so only a Read that ran)
#   instructions-check.py  <read suffix> <instruction file suffix>: prints one line,
#                          instructions-hook=live|silent trigger=read|unread
#                          <instruction file suffix>=loaded|absent
set -euo pipefail
d="${1:?usage: instructions-probe.sh <dir>}"
hub="$d/repos/github.com/acme/hub"
target="$d/repos/github.com/acme/target"
[[ -d "$hub/.git" && -d "$target/.git" ]] ||
  { echo "instructions-probe.sh: run hub-layout.sh $d first" >&2; exit 2; }
mkdir -p "$hub/docs"
printf '# hub\n\nProbe fixture: hub instructions.\n' >"$hub/CLAUDE.md"
printf '# hub docs\n\nProbe fixture: hub docs instructions.\n' >"$hub/docs/CLAUDE.md"
printf '# Guide\n\nstatus: one\n' >"$hub/docs/guide.md"
printf '# target\n\nProbe fixture: target instructions.\n' >"$target/CLAUDE.md"

cat >"$d/instructions-log.py" <<'EOF'
import json
import sys
from pathlib import Path

payload = json.load(sys.stdin)
event = payload.get("hook_event_name")
if event == "InstructionsLoaded":
    line = f"loaded {payload.get('file_path')}"
elif event == "PostToolUse":
    line = f"read {(payload.get('tool_input') or {}).get('file_path')}"
else:
    sys.exit(0)
log = Path(__file__).resolve().parent / "instructions.log"
with log.open("a", encoding="utf-8") as fh:
    fh.write(line.replace("\\", "/") + "\n")
EOF

cat >"$d/instructions-check.py" <<'EOF'
import sys
from pathlib import Path

trigger, instructions = sys.argv[1], sys.argv[2]
log = Path(__file__).resolve().parent / "instructions.log"
lines = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
loaded = [line[len("loaded "):] for line in lines if line.startswith("loaded ")]
reads = [line[len("read "):] for line in lines if line.startswith("read ")]
hook = "live" if loaded else "silent"
read = "read" if any(p.endswith(trigger) for p in reads) else "unread"
state = "loaded" if any(p.endswith(instructions) for p in loaded) else "absent"
print(f"instructions-hook={hook} trigger={read} {instructions}={state}")
EOF
