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

# --- the engine is read ONCE per launch, and that read stops at MIN_PYTHON ---
#
# #2853. This launcher sits behind an always-on `Bash|PowerShell` PreToolUse
# matcher, so every shell tool call in every session pays whatever it does here.
# It used to run two separate full-file `sed` passes over the ~3,500-line
# engine, neither of which stopped at the match, to recover one constant that
# sits near the top of the file.
#
# Both assertions below are BEHAVIORAL, not spelling checks. They observe the
# reader the launcher actually runs, through a `sed` shim on PATH that records
# each invocation's argv and delegates to the real sed:
#
#   1. exactly one recorded invocation names the engine;
#   2. replaying that recorded argv against a fixture whose FIRST `MIN_PYTHON`
#      line is `(3, 14)` and whose LAST LINE is `MIN_PYTHON = (9, 99)` prints
#      exactly one line. A reader that scanned to EOF could not print one match
#      when a second match sits on the final line, so one line is proof the read
#      terminated at the first match.
#
# Assertion 2 is what a naive single-pass cannot fake: the tempting one-liner
# `sed -n 's/^MIN_PYTHON = (...).*/\1 \2/p;/^MIN_PYTHON/q'` halves the passes but
# never quits, because `q`'s address sees the already-substituted pattern space.
# The fixture's floor values are deliberately NOT the real 3/11, so the
# launcher's hardcoded fallback cannot be mistaken for a pass.
SED_REAL="$(command -v sed)"
PROBE_DIR="$(mktemp -d)"
# NOTE: the later `trap ... EXIT` in this file REPLACES this one rather than
# adding to it, so it removes both directories. Keep them in sync.
trap 'rm -rf "$PROBE_DIR"' EXIT
PROBE_BIN="$PROBE_DIR/bin"
PROBE_CALLS="$PROBE_DIR/calls"
mkdir -p "$PROBE_BIN" "$PROBE_CALLS"

cat >"$PROBE_BIN/sed" <<'SHIM'
#!/usr/bin/env bash
# Record this invocation's argv when the engine is among its operands, then
# delegate to the real sed. One newline-separated file per recorded call.
set -uo pipefail
for arg in "$@"; do
  case "$arg" in
  *"/skills/clean/scripts/hygiene.py")
    idx=1
    while [[ -e "$RUN_PYTHON_HOOK_CALLS/call-$idx" ]]; do
      idx=$((idx + 1))
    done
    printf '%s\n' "$@" >"$RUN_PYTHON_HOOK_CALLS/call-$idx"
    break
    ;;
  esac
done
exec "$RUN_PYTHON_HOOK_SED" "$@"
SHIM
chmod +x "$PROBE_BIN/sed"

# No interpreter resolves under this PATH, so the launcher takes its documented
# guard fail-open (exit 0) instead of spawning Python. The engine read happens
# before interpreter resolution either way, which is the whole point.
for stub in python3 python py; do
  printf '#!/usr/bin/env bash\nexit 127\n' >"$PROBE_BIN/$stub"
  chmod +x "$PROBE_BIN/$stub"
done

PROBE_FIXTURE="$PROBE_DIR/fixture.py"
{
  printf '%s\n' '"""Fixture engine for the single-read contract."""'
  printf '%s\n' 'MIN_PYTHON = (3, 14)'
  for ((_filler = 0; _filler < 400; _filler++)); do
    printf '%s\n' 'FILLER = 0'
  done
  printf '%s\n' 'MIN_PYTHON = (9, 99)'
} >"$PROBE_FIXTURE"

RUN_PYTHON_HOOK_SED="$SED_REAL" \
  RUN_PYTHON_HOOK_CALLS="$PROBE_CALLS" \
  PATH="$PROBE_BIN:$PATH" \
  bash "$LAUNCHER" \
  "$SCRIPT_DIR/../skills/clean/scripts/destructive_guard.py" \
  --mode engine-gate >/dev/null 2>&1 || true

engine_reads=0
for call in "$PROBE_CALLS"/call-*; do
  [[ -e "$call" ]] || continue
  engine_reads=$((engine_reads + 1))
done
assert_eq "one hook launch reads the engine exactly once" "1" "$engine_reads"

if [[ "$engine_reads" -ne 1 ]]; then
  fail "cannot check the stop-at-match contract without exactly one recorded read"
fi

recorded_argv=()
while IFS= read -r recorded_arg; do
  recorded_argv+=("$recorded_arg")
done <"$PROBE_CALLS/call-1"

# Replay the SAME argv, with the engine operand swapped for the fixture.
replay_argv=()
for recorded_arg in "${recorded_argv[@]}"; do
  case "$recorded_arg" in
  *"/skills/clean/scripts/hygiene.py") replay_argv+=("$PROBE_FIXTURE") ;;
  *) replay_argv+=("$recorded_arg") ;;
  esac
done

replay_out="$("$SED_REAL" "${replay_argv[@]}")"
replay_lines="$(printf '%s\n' "$replay_out" | grep -c . || true)"
assert_eq "the engine read stops at the MIN_PYTHON line instead of scanning to EOF" \
  "1" "$replay_lines"
assert_eq "the stopped read yields the fixture's first floor" \
  "3 14" "${replay_out//$'\r'/}"

# Same replay against the REAL engine: the refinement must still produce the
# floor the two-pass form produced, which is what keeps MIN_PYTHON the single
# origin (#1028) rather than a second hardcoded copy.
real_out="$("$SED_REAL" "${recorded_argv[@]}")"
assert_eq "the single read recovers the engine's real floor" \
  "${FLOOR/./ }" "${real_out//$'\r'/}"

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
# Replaces (does not chain onto) the earlier EXIT trap, so it cleans up both.
trap 'rm -rf "$FAKE_BIN" "$PROBE_DIR"' EXIT
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
