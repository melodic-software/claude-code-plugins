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
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

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

# --- the engine is NOT read by this launcher, and the floor still comes from it ---
#
# The launcher recovers the floor INSIDE the candidate interpreter, on the cold
# path only, so it spends one process spawn per candidate and never reads the
# engine file itself (#3502).
#
# The contract has two halves, because deleting a cost must not quietly delete
# the property that cost was buying:
#
#   1. no launch reads the engine through `sed` at all: the recorded-argv shim
#      below observes zero invocations naming the engine;
#   2. `hygiene.MIN_PYTHON` is still the single origin of the floor (#1028) and
#      is still ENFORCED, proven behaviorally against fixture engines by
#      observing whether the launcher runs its target at all.
#
# Half 2 is what a "delete the reader" regression cannot fake. A launcher that
# stopped consulting the engine would run its target under both fixtures.
SED_REAL="$(command -v sed)"
PROBE_DIR="$(mktemp -d)"
# NOTE: the later `trap ... EXIT` in this file REPLACES this one rather than
# adding to it, so it removes both directories. Keep them in sync.
trap 'rm -rf "$PROBE_DIR"' EXIT
PROBE_BIN="$PROBE_DIR/bin"
PROBE_CALLS="$PROBE_DIR/calls"
PROBE_HOME="$PROBE_DIR/home"
mkdir -p "$PROBE_BIN" "$PROBE_CALLS" "$PROBE_HOME"

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
# guard fail-open (exit 0). Whether it reads the engine is independent of that.
for stub in python3 python py; do
  printf '#!/usr/bin/env bash\nexit 127\n' >"$PROBE_BIN/$stub"
  chmod +x "$PROBE_BIN/$stub"
done

RUN_PYTHON_HOOK_SED="$SED_REAL" \
  RUN_PYTHON_HOOK_CALLS="$PROBE_CALLS" \
  HOME="$PROBE_HOME" \
  PATH="$PROBE_BIN:$PATH" \
  bash "$LAUNCHER" \
  "$SCRIPT_DIR/../skills/clean/scripts/destructive_guard.py" \
  --mode engine-gate >/dev/null 2>&1 || true

engine_reads=0
for call in "$PROBE_CALLS"/call-*; do
  [[ -e "$call" ]] || continue
  engine_reads=$((engine_reads + 1))
done
assert_eq "the launcher never sed-reads the engine" "0" "$engine_reads"

# --- the floor is still read from the engine, and still enforced ---
#
# A fixture plugin tree: a verbatim copy of the launcher, a fixture engine
# carrying a chosen MIN_PYTHON, and a target script that leaves a marker file
# when it runs. The launcher resolves `ENGINE` relative to its own location, so
# copying it into the fixture tree is what points it at the fixture engine.
FIXTURE_ROOT="$PROBE_DIR/plugin"
mkdir -p "$FIXTURE_ROOT/hooks" "$FIXTURE_ROOT/skills/clean/scripts"
cp "$LAUNCHER" "$FIXTURE_ROOT/hooks/run-python-hook.sh"
FIXTURE_TARGET="$FIXTURE_ROOT/skills/clean/scripts/destructive_guard.py"
FIXTURE_MARKER="$PROBE_DIR/target-ran"
printf 'import pathlib, sys\npathlib.Path(sys.argv[1]).write_text("ran")\n' \
  >"$FIXTURE_TARGET"

# `written_floor <major> <minor>` rewrites the fixture engine's floor. The
# SECOND MIN_PYTHON line is a decoy on the final line: a reader that scanned to
# EOF and kept the last match would take (9, 99) and reject every interpreter,
# so the "below the floor" case passing is also proof the read is first-match.
write_fixture_engine() {
  {
    printf '%s\n' '"""Fixture engine for the version-floor contract."""'
    printf 'MIN_PYTHON = (%s, %s)\n' "$1" "$2"
    printf '%s\n' 'FILLER = 0'
    printf '%s\n' 'MIN_PYTHON = (9, 99)'
  } >"$FIXTURE_ROOT/skills/clean/scripts/hygiene.py"
}

# Each case gets its OWN HOME, so the interpreter cache of one never answers
# for another — the cache is keyed on the launcher's directory, which these
# two cases share.
run_fixture() {
  local floor_major="$1" floor_minor="$2" case_home="$PROBE_DIR/home-$1-$2"
  write_fixture_engine "$floor_major" "$floor_minor"
  rm -f "$FIXTURE_MARKER"
  mkdir -p "$case_home"
  HOME="$case_home" bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
  [[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped'
}

assert_eq "an engine floor at or below the running interpreter runs the target" \
  "ran" "$(run_fixture 3 0)"
assert_eq "an engine floor above every interpreter refuses to run the target" \
  "skipped" "$(run_fixture 99 0)"

# The real engine's real floor must still resolve to a runnable interpreter —
# the property the deleted `sed` read was buying, restated as an outcome.
rm -f "$FIXTURE_MARKER"
cp "$SCRIPT_DIR/../skills/clean/scripts/hygiene.py" \
  "$FIXTURE_ROOT/skills/clean/scripts/hygiene.py"
FIXTURE_REAL_HOME="$PROBE_DIR/home-real"
mkdir -p "$FIXTURE_REAL_HOME"
HOME="$FIXTURE_REAL_HOME" bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
  "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
assert_eq "the engine's real floor still admits this host's interpreter" \
  "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"

# --- the resolved interpreter is cached, and the cache invalidates correctly ---
#
# The launcher sits behind an always-on `Bash|PowerShell` matcher, so the cost
# that matters is what a WARM invocation spends. These assertions observe spawns
# through a counting interpreter shim: a cold launch resolves (probe spawn plus
# the target) and a warm launch must reach the target having probed nothing.
CACHE_ROOT="$PROBE_DIR/cache-case"
CACHE_BIN="$CACHE_ROOT/bin"
CACHE_HOME="$CACHE_ROOT/home"
CACHE_LOG="$CACHE_ROOT/python-calls"
mkdir -p "$CACHE_BIN" "$CACHE_HOME"
REAL_PYTHON="$(command -v python3 || true)"
if [[ -z "$REAL_PYTHON" ]]; then
  printf 'SKIP: no python3 on PATH; cache contract not exercised\n'
else
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "call\\n" >>"%s"\n' "$CACHE_LOG"
    printf 'exec "%s" "$@"\n' "$REAL_PYTHON"
  } >"$CACHE_BIN/python3"
  chmod +x "$CACHE_BIN/python3"

  cache_launch() {
    : >"$CACHE_LOG"
    rm -f "$FIXTURE_MARKER"
    HOME="$CACHE_HOME" PATH="$CACHE_BIN:$PATH" \
      bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
    grep -c . "$CACHE_LOG" 2>/dev/null || printf '0'
  }

  cold_calls="$(cache_launch)"
  assert_eq "a cold launch spends a version probe on top of the target" \
    "2" "$cold_calls"
  warm_calls="$(cache_launch)"
  assert_eq "a warm launch spawns only the target, no probe" "1" "$warm_calls"
  assert_eq "a warm launch still runs the target" \
    "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"

  cache_record="$(find "$CACHE_HOME/.cache/disk-hygiene" -name 'interpreter-*' \
    -type f 2>/dev/null | head -n 1)"
  if [[ -z "$cache_record" ]]; then
    fail "no interpreter cache record was written"
  fi
  pass "the cache record is keyed per launcher directory, not a shared file"

  # PATH is part of the key: a different PATH may resolve a different python3.
  altered_path_calls="$(
    : >"$CACHE_LOG"
    HOME="$CACHE_HOME" PATH="$CACHE_BIN:$PROBE_DIR:$PATH" \
      bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
    grep -c . "$CACHE_LOG" 2>/dev/null || printf '0'
  )"
  assert_eq "a changed PATH invalidates the cached interpreter" \
    "2" "$altered_path_calls"

  # An interpreter modified after the record was written is not the one that
  # was validated — the in-place-upgrade case.
  cache_launch >/dev/null
  touch "$CACHE_BIN/python3"
  upgraded_calls="$(cache_launch)"
  assert_eq "an interpreter newer than the record invalidates the cache" \
    "2" "$upgraded_calls"

  # A record from a future schema is not readable by this launcher.
  cache_launch >/dev/null
  printf 'schema=999\nwritten=1\ninterpreter=/nonexistent\npath=%s\n' "$PATH" \
    >"$cache_record"
  schema_calls="$(cache_launch)"
  assert_eq "a foreign schema invalidates the cached interpreter" \
    "2" "$schema_calls"

  # An expired record is re-resolved rather than trusted. The staleness is
  # forged in the RECORD (an old `written=` epoch), not through an environment
  # override: the TTL is compiled in precisely so it cannot be widened by the
  # environment, and a test that reached for such a knob would be asserting a
  # channel this launcher deliberately does not have.
  cache_launch >/dev/null
  cached_interp="$(sed -n 's/^interpreter=//p' "$cache_record")"
  {
    printf 'schema=1\n'
    printf 'written=%s\n' "1"
    printf 'interpreter=%s\n' "$cached_interp"
    printf 'path=%s\n' "$CACHE_BIN:$PATH"
  } >"$cache_record"
  ttl_calls="$(cache_launch)"
  assert_eq "an expired record is re-resolved" "2" "$ttl_calls"

  # A corrupt record must fall back to full resolution — never to "no
  # interpreter", which is the guard's silent fail-open.
  cache_launch >/dev/null
  printf 'this is not a cache record\n' >"$cache_record"
  rm -f "$FIXTURE_MARKER"
  corrupt_calls="$(cache_launch)"
  assert_eq "a corrupt record falls back to resolution" "2" "$corrupt_calls"
  assert_eq "a corrupt record still runs the target" \
    "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"

  # A record naming a NON-INTERPRETER is the cache's residual exposure, and it
  # is recorded here as a known limit rather than a passing property: the hot
  # path validates SHAPE only (`-x`, `-s`, an interpreter basename), because
  # proving the binary is really Python costs the very spawn the cache exists
  # to remove. A shape-valid record pointing at an executable that is not an
  # interpreter is therefore `exec`'d, the guard never runs, and the hook exits
  # 0 having enforced nothing.
  #
  # The assertion below pins the boundary that IS enforced — a non-interpreter
  # BASENAME is rejected and re-resolved — so a future change that widened the
  # basename allowlist would fail here.
  cache_launch >/dev/null
  cached_interp="$(sed -n 's/^interpreter=//p' "$cache_record")"
  IMPOSTOR_DIR="$CACHE_ROOT/impostor"
  mkdir -p "$IMPOSTOR_DIR"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$IMPOSTOR_DIR/node"
  chmod +x "$IMPOSTOR_DIR/node"
  {
    printf 'schema=1\n'
    printf 'written=%s\n' "$(date +%s)"
    printf 'interpreter=%s\n' "$IMPOSTOR_DIR/node"
    printf 'path=%s\n' "$CACHE_BIN:$PATH"
  } >"$cache_record"
  rm -f "$FIXTURE_MARKER"
  impostor_calls="$(cache_launch)"
  assert_eq "a record naming a non-interpreter basename is re-resolved" \
    "2" "$impostor_calls"
  assert_eq "and the target still runs under a real interpreter" \
    "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"

  # A NATIVE WINDOWS interpreter path must be accepted from the cache.
  #
  # The `py -3` fallback resolves through `print(sys.executable)`, which on
  # Windows emits `C:\...\python.exe`. A basename check that split only on `/`
  # left the whole backslash path in place, the allowlist never matched, and the
  # record was rejected on EVERY invocation — so the warm path was dead on
  # exactly the host class the `py` fallback exists for (neither `python3` nor
  # `python` on PATH), silently and with no error. Nothing in the previous
  # contract set caught it, because every path this suite produced was POSIX.
  if command -v cygpath >/dev/null 2>&1; then
    cache_launch >/dev/null
    native_shim="$(cygpath -w "$CACHE_BIN/python3")"
    {
      printf 'schema=1\n'
      printf 'written=%s\n' "$(date +%s)"
      printf 'interpreter=%s\n' "$native_shim"
      printf 'path=%s\n' "$CACHE_BIN:$PATH"
    } >"$cache_record"
    rm -f "$FIXTURE_MARKER"
    native_calls="$(cache_launch)"
    assert_eq "a native Windows interpreter path is accepted from the cache" \
      "1" "$native_calls"
    assert_eq "and the target runs under it" \
      "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"
  else
    printf 'SKIP: no cygpath; native-path cache acceptance not exercised\n'
  fi

  # An unwritable cache directory must not stop the launcher from working.
  NOCACHE_HOME="$CACHE_ROOT/home-readonly"
  mkdir -p "$NOCACHE_HOME"
  rm -f "$FIXTURE_MARKER"
  HOME="$NOCACHE_HOME/does-not-exist" PATH="$CACHE_BIN:$PATH" \
    bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
  assert_eq "an unusable cache location still runs the target" \
    "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"
fi

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
for stub in python3 python; do
  printf '#!/usr/bin/env bash\nexit 127\n' >"$FAKE_BIN/$stub"
  chmod +x "$FAKE_BIN/$stub"
done

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

# --- a warm launch creates no process before it execs the interpreter ---
#
# Both engine-gate entries carry an `if` filter, so this launcher now runs only
# for a shell call that names the engine; what such a call pays is the spawn
# chain itself, and a warm launch must add nothing to it. The census is taken at
# the kernel (`strace -f`), not through a PATH shim or `set -x`: a fork that
# never execs (a `$(...)` substitution, a pipeline) is invisible to both, and a
# fork is the unit Windows charges for. Expected on a warm cache: zero
# clone/fork calls, and exactly two execve calls, bash running the launcher and
# the resolved interpreter running the target. Skipped where strace is absent,
# where ptrace is refused, or where `python3` is itself a script (a version
# manager shim), since that shim's own spawns are not this launcher's.
if ! command -v strace >/dev/null 2>&1; then
  echo "SKIP: strace not available for the spawn census" >&2
elif [[ -z "$REAL_PYTHON" ]] || [[ "$(head -c 2 "$REAL_PYTHON" 2>/dev/null)" == "#!" ]]; then
  echo "SKIP: python3 is absent or is a shim script; spawn census not exercised" >&2
elif ! strace -qq -e trace=execve -o /dev/null true >/dev/null 2>&1; then
  echo "SKIP: strace cannot trace on this host; spawn census not exercised" >&2
else
  CENSUS_HOME="$PROBE_DIR/census-home"
  CENSUS_LOG="$PROBE_DIR/census.strace"
  mkdir -p "$CENSUS_HOME"
  # Cold launch: resolves and writes the cache record under the census HOME.
  HOME="$CENSUS_HOME" bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
  rm -f "$FIXTURE_MARKER"
  HOME="$CENSUS_HOME" strace -f -qq -e trace=clone,clone3,fork,vfork,execve \
    -o "$CENSUS_LOG" bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
  assert_eq "the traced warm launch still runs the target" \
    "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"
  # A creation is a clone/fork line that returned a child id; the `unfinished`
  # half of a split line is excluded so a creation is counted once.
  census_creations="$(grep -E '\b(clone3?|v?fork)\b' "$CENSUS_LOG" |
    grep -v unfinished | grep -cE '= [1-9][0-9]*$' || true)"
  census_execs="$(grep -E '^[0-9]+ +execve\(' "$CENSUS_LOG" |
    grep -cE '\) = 0$' || true)"
  assert_eq "a warm launch creates no process before exec (strace census)" \
    "0" "$census_creations"
  assert_eq "a warm launch execs exactly bash and the interpreter (strace census)" \
    "2" "$census_execs"
fi

pass "all run-python-hook contract checks"
