#!/usr/bin/env bash
# Contract tests for run-python-hook.sh (#1504, #1505).
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="$HOOK_DIR/run-python-hook.sh"
PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS=0
FAIL=0

assert_exit() {
  local label="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then
    echo "ok: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (want exit $want, got $got)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    echo "ok: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label ($needle not in output)"
    FAIL=$((FAIL + 1))
  fi
}

# Happy path: launcher forwards to a tiny Python script.
HELPER="$TEST_TMPDIR/echo_rc.py"
cat >"$HELPER" <<'PY'
import sys
print("ran")
sys.exit(0)
PY

OUT=$(bash "$LAUNCHER" test-hook PreToolUse "$HELPER" 2>&1)
RC=$?
assert_exit "forwards to python script" 0 "$RC"
assert_contains "python script stdout" "$OUT" "ran"

# PreToolUse fail-closed when no interpreter resolves.
OUT=$(DISK_HYGIENE_FORCE_NO_PYTHON=1 bash "$LAUNCHER" disk-hygiene-destructive-guard PreToolUse "$HELPER" <<<"{}" 2>&1)
RC=$?
assert_exit "missing interpreter on PreToolUse → exit 2" 2 "$RC"
assert_contains "missing interpreter → deny decision" "$OUT" '"permissionDecision":"deny"'

# Stop hook surfaces interpreter gap without blocking.
OUT=$(DISK_HYGIENE_FORCE_NO_PYTHON=1 bash "$LAUNCHER" disk-hygiene-guard-launch-monitor Stop "$HELPER" <<<"{}" 2>&1)
RC=$?
assert_exit "missing interpreter on Stop → exit 0" 0 "$RC"
assert_contains "missing interpreter on Stop → systemMessage" "$OUT" "no runnable Python interpreter"

# Telemetry envelope when sink is wired.
TEL="$TEST_TMPDIR/telemetry.jsonl"
SINK="$TEST_TMPDIR/sink.sh"
cat >"$SINK" <<EOF
#!/usr/bin/env bash
cat >>"$TEL"
EOF
chmod +x "$SINK"
export HOOK_TELEMETRY_SINK="$SINK"
export EPOCHREALTIME=1000.0
: >"$TEL"
OUT=$(bash "$LAUNCHER" disk-hygiene-destructive-guard PreToolUse "$HELPER" <<<"{}" 2>&1)
RC=$?
assert_exit "telemetry path → script still runs" 0 "$RC"
sleep 0.2
if [[ -s "$TEL" ]]; then
  echo "ok: telemetry sink received a line"
  PASS=$((PASS + 1))
  assert_contains "telemetry hook id" "$(jq -r '.hook' "$TEL" 2>/dev/null)" "disk-hygiene-destructive-guard"
else
  echo "FAIL: telemetry sink empty"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
