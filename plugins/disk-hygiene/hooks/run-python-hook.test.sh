#!/usr/bin/env bash
# Contract tests for the disk-hygiene Python hook launcher (#1504).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="$SCRIPT_DIR/run-python-hook.sh"

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (missing '$needle' in output)"
  fi
}

# --- launcher is executable and hooks.json wires bash + this script ---
HOOKS_JSON="$SCRIPT_DIR/hooks.json"
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required" >&2
  exit 0
fi

for hook_name in destructive_guard.py guard_launch_monitor.py; do
  command_line="$(jq -r --arg target "$hook_name" '
    .hooks | to_entries[] | .value[]? | .hooks[]? |
    select(.args[]? | contains($target)) | .command
  ' "$HOOKS_JSON" | head -n1)"
  assert_eq "hooks.json command for $hook_name is bash" "bash" "$command_line"
  launcher_arg="$(jq -r --arg target "$hook_name" '
    .hooks | to_entries[] | .value[]? | .hooks[]? |
    select(.args[]? | contains($target)) | .args[0]
  ' "$HOOKS_JSON" | head -n1)"
  assert_contains "hooks.json args[0] for $hook_name is the launcher" "run-python-hook.sh" "$launcher_arg"
done

# --- monitor mode without python emits systemMessage JSON ---
FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN"' EXIT
printf '#!/usr/bin/env bash\nexit 127\n' >"$FAKE_BIN/nopy"
chmod +x "$FAKE_BIN/nopy"
cat >"$FAKE_BIN/python3" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$FAKE_BIN/python3"
cat >"$FAKE_BIN/python" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$FAKE_BIN/python"

MONITOR_OUT="$(
  PATH="$FAKE_BIN:$PATH" bash "$LAUNCHER" \
    "$SCRIPT_DIR/../skills/clean/scripts/guard_launch_monitor.py" \
    --data-root /tmp/disk-hygiene-test 2>/dev/null || true
)"
assert_contains "monitor mode warns when python is unavailable" "systemMessage" "$MONITOR_OUT"
assert_contains "monitor mode names the guard" "destructive guard" "$MONITOR_OUT"

# --- guard mode without python is silent success ---
GUARD_RC=0
PATH="$FAKE_BIN:$PATH" bash "$LAUNCHER" \
  "$SCRIPT_DIR/../skills/clean/scripts/destructive_guard.py" \
  --mode engine-gate >/dev/null 2>&1 || GUARD_RC=$?
assert_eq "guard mode exits 0 when python is unavailable" "0" "$GUARD_RC"

# --- happy path execs the target script when python is available ---
if command -v python3 >/dev/null 2>&1 &&
  python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
  HELPER="$(mktemp --suffix=.py)"
  printf 'import sys\nprint("launcher-ok")\n' >"$HELPER"
  HELPER_OUT="$(bash "$LAUNCHER" "$HELPER" 2>/dev/null || true)"
  rm -f "$HELPER"
  assert_eq "launcher runs python script on happy path" "launcher-ok" "${HELPER_OUT//$'\r'/}"
else
  echo "SKIP: runnable python3 not available for happy-path probe" >&2
fi

pass "all run-python-hook contract checks"
