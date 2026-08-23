#!/usr/bin/env bash
# Cross-platform contract wrapper for the audit-performance engine test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the engine. Parse it rather
# than restating the number here.
ENGINE="$SCRIPT_DIR/audit_performance.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

"$PYTHON" -c "import sys; floor = tuple(int(p) for p in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" || {
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
}

(cd "$SCRIPT_DIR" && "$PYTHON" -m unittest -v test_audit_performance)

# End-to-end contract checks against a synthetic install root. These assert the
# shipped report SHAPE, which the unit suite cannot: a probe can be correct in
# isolation and still be missing from the JSON an operator actually reads.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/plugins"
cat >"$WORK/root/settings.json" <<'JSON'
{
  "env": {"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "5"},
  "statusLine": {"type": "command", "command": "bash line.sh", "refreshInterval": 2},
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "stop.sh"}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "pre.sh"}]}]
  }
}
JSON

REPORT="$WORK/report.json"
"$PYTHON" "$ENGINE" --root "$WORK/root" --skip-processes --spawn-samples 1 >"$REPORT"

"$PYTHON" - "$REPORT" <<'PY'
import json
import sys

report = json.loads(open(sys.argv[1], encoding="utf-8").read())
fan_out = report.get("fan_out")
assert fan_out, "the report ships no fan_out section; the fourth suspect is invisible"

hooks = fan_out["hooks"]
assert hooks["per_turn"]["count"] == 1, hooks["per_turn"]
assert hooks["per_tool_call"]["count"] == 1, hooks["per_tool_call"]

depth = fan_out["concurrency_ceilings"]["variables"]["CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"]
assert depth["above_documented_default"] is True, depth
assert fan_out["statusline"]["configured"] is True, fan_out["statusline"]
assert "spawn_cost" in fan_out and "state_label" in fan_out["spawn_cost"], fan_out["spawn_cost"]
assert "fan_out" in report["timings_seconds"], report["timings_seconds"]
print("OK: fan-out layer is present in the shipped report")
PY

# --skip-fan-out must actually skip it, so an operator on a wedged machine can
# still capture the other three suspects.
"$PYTHON" "$ENGINE" --root "$WORK/root" --skip-processes --skip-fan-out >"$WORK/lean.json"
"$PYTHON" - "$WORK/lean.json" <<'PY'
import json
import sys

report = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert "fan_out" not in report, "--skip-fan-out did not skip the fan-out probes"
assert "tree_census" in report, "skipping fan-out must not drop the other phases"
print("OK: --skip-fan-out honored")
PY
