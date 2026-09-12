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
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "pre.sh"}]}],
    "PostToolUse": [{"matcher": "Write|Edit", "hooks": [
      {"type": "command", "command": "fmt.sh", "if": "Edit(*.md)"},
      {"type": "command", "command": "wide.sh", "if": "Edit(*.{md,mdc})"}
    ]}],
    "PermissionDenied": [{"hooks": [{"type": "command", "command": "deny.sh"}]}]
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
assert hooks["per_tool_call"]["count"] == 4, hooks["per_tool_call"]
assert hooks["per_tool_call"]["if_gated_rows"] == 2, hooks["per_tool_call"]
assert hooks["per_tool_call"]["distinct_commands"] == 4, hooks["per_tool_call"]

# PermissionDenied is one of the five events that accept `if`, so it is per tool call.
assert hooks["by_event"]["PermissionDenied"] == 1, hooks["by_event"]
assert hooks["other"]["count"] == 0, hooks["other"]

gated = next(
    r for r in hooks["by_matcher"]
    if r["event"] == "PostToolUse" and r["matcher"] == "Write|Edit"
)
assert gated["rows"] == 2 and gated["if_gated_rows"] == 2, gated
assert gated["distinct_commands"] == 2, gated

projected = {
    (r["event"], r["tool"], r["file_kind"]): r for r in hooks["projection"]["rows"]
}
markdown = projected[("PostToolUse", "Edit", ".md")]
assert markdown["fires"] == 2, markdown
assert markdown["fire_always_unclassified"] == 1, markdown
assert projected[("PostToolUse", "Edit", ".json")]["fires"] == 1, projected

unclassified = hooks["unclassified_rows"]
assert [r["if"] for r in unclassified] == ["Edit(*.{md,mdc})"], unclassified
assert unclassified[0]["reason"], unclassified

joined = " ".join(hooks["notes"])
assert "outside the project directory" in joined, hooks["notes"]
assert "it runs once" in joined, hooks["notes"]
assert "parallel" in joined, hooks["notes"]
print("OK: the hook block ships by_matcher, the projection, and unclassified rows")

depth = fan_out["concurrency_ceilings"]["variables"]["CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"]
assert depth["above_documented_default"] is True, depth
assert fan_out["statusline"]["configured"] is True, fan_out["statusline"]
assert "spawn_cost" in fan_out and "state_label" in fan_out["spawn_cost"], fan_out["spawn_cost"]
assert "fan_out" in report["timings_seconds"], report["timings_seconds"]
print("OK: fan-out layer is present in the shipped report")

context = report.get("operator_context")
assert context is not None, "the report ships no operator_context; the missing paragraph is invisible"
assert context["status"] == "absent" and context["notes"] == [], context
assert context["source"] == "unspecified", context
print("OK: an absent operator paragraph is reported as a fact, not omitted")

census = report.get("kernel_objects")
assert census is not None and "supported" in census, (
    "the report ships no kernel_objects section; the host-level floor is invisible"
)
assert census["supported"] is False or census["state_label"] in {"nominal", "paged-pool-high", "token-leak"}, census
assert "kernel_objects" in report["timings_seconds"], report["timings_seconds"]
print("OK: kernel-object census is present in the shipped report")
PY

# Repeated --note lands in the shipped report with its declared source, so the
# context only a human at the machine holds survives into the artifact.
"$PYTHON" "$ENGINE" --root "$WORK/root" --skip-processes --skip-fan-out \
  --note "typing lagged" --note "four terminals open" --note-source operator \
  >"$WORK/noted.json"
"$PYTHON" - "$WORK/noted.json" <<'PY'
import json
import sys

context = json.loads(open(sys.argv[1], encoding="utf-8").read())["operator_context"]
assert context["status"] == "present", context
assert context["notes"] == ["typing lagged", "four terminals open"], context
assert context["source"] == "operator", context
print("OK: repeated --note reaches the shipped report with its declared source")
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
assert "kernel_objects" in report, "skipping fan-out must not drop the host-level floor"
print("OK: --skip-fan-out honored")
PY
