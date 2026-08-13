#!/usr/bin/env bash
# Contract tests for the disk-hygiene Python hook launcher (#1504).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="$SCRIPT_DIR/run-python-hook.sh"
ENGINE="$SCRIPT_DIR/../skills/clean/scripts/hygiene.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi
PYTHON_VERSION_PROBE="import sys; floor = tuple(int(part) for part in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)"

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

# --- hooks.json wires this launcher in portable shell form ---
#
# These assert the PORTABILITY PROPERTY, not a literal spelling. The previous
# revision asserted `.command == "bash"` with the script in `.args`, which
# encoded the #1006 defect as the contract: exec form (`args` present) resolves
# `command` as a bare PATH lookup, and on Windows `bash` finds the WSL relay
# `System32\bash.exe` before Git Bash. The launch fails, and a failed hook
# launch is non-blocking — so the guard silently enforced nothing.
HOOKS_JSON="$SCRIPT_DIR/hooks.json"
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required" >&2
  exit 0
fi

for hook_name in destructive_guard.py guard_launch_monitor.py; do
  entry="$(jq -c --arg target "$hook_name" '
    .hooks | to_entries[] | .value[]? | .hooks[]? |
    select(.command | contains($target))
  ' "$HOOKS_JSON" | head -n1)"
  if [[ -z "$entry" ]]; then
    fail "hooks.json has no command hook referencing $hook_name"
  fi

  command_line="$(jq -r '.command' <<<"$entry")"
  assert_contains "hooks.json command for $hook_name invokes the launcher" \
    "run-python-hook.sh" "$command_line"

  # Shell form only: `args` present would switch Claude Code to exec form, where
  # `command` is a bare PATH lookup and `shell` is ignored.
  assert_eq "hooks.json entry for $hook_name omits args (shell form)" \
    "null" "$(jq -r '.args // "null" | if type == "array" then "present" else . end' <<<"$entry")"

  # Explicit `shell: bash`. Shell form otherwise falls back to PowerShell on a
  # Windows host with no Git Bash detected, which cannot run a .sh launcher.
  assert_eq "hooks.json entry for $hook_name declares shell bash" \
    "bash" "$(jq -r '.shell // ""' <<<"$entry")"

  # Every path placeholder must be double-quoted: the shell re-tokenizes the
  # command string, and plugin roots routinely contain spaces.
  unquoted="$(grep -oE '(^|[^"])\$\{CLAUDE_PLUGIN_(ROOT|DATA)\}|\$\{CLAUDE_PLUGIN_(ROOT|DATA)\}([^"]|$)' <<<"$command_line" || true)"
  if [[ -n "$unquoted" ]]; then
    fail "hooks.json command for $hook_name has an unquoted path placeholder: $unquoted"
  fi
  pass "hooks.json command for $hook_name double-quotes every path placeholder"
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
  python3 -c "$PYTHON_VERSION_PROBE" 2>/dev/null; then
  HELPER="$(mktemp --suffix=.py)"
  printf 'import sys\nprint("launcher-ok")\n' >"$HELPER"
  HELPER_OUT="$(bash "$LAUNCHER" "$HELPER" 2>/dev/null || true)"
  rm -f "$HELPER"
  assert_eq "launcher runs python script on happy path" "launcher-ok" "${HELPER_OUT//$'\r'/}"
else
  echo "SKIP: runnable python3 not available for happy-path probe" >&2
fi

pass "all run-python-hook contract checks"
