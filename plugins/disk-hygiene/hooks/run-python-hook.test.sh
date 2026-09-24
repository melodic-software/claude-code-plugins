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
# that matters is what a WARM invocation spends. These assertions count version
# probes through an interpreter shim: a cold launch probes once, and a warm
# launch must reach the target having probed nothing. The cache records the
# probe's `sys.executable`, so the target runs on the real interpreter and never
# passes through the shim.
CACHE_ROOT="$PROBE_DIR/cache-case"
CACHE_BIN="$CACHE_ROOT/bin"
CACHE_HOME="$CACHE_ROOT/home"
CACHE_LOG="$CACHE_ROOT/python-calls"
mkdir -p "$CACHE_BIN" "$CACHE_HOME"
REAL_PYTHON="$(command -v python3 || true)"
if [[ -z "$REAL_PYTHON" ]]; then
  printf 'SKIP: no python3 on PATH; cache contract not exercised\n'
else
  # `write_counting_shim <dir> <log>`: a `python3` that logs its first argument
  # and runs the real interpreter. A version probe's first argument is `-c`.
  write_counting_shim() {
    mkdir -p "$1"
    {
      printf '#!/usr/bin/env bash\n'
      # shellcheck disable=SC2016  # `$1` is the shim's, deliberately unexpanded
      printf 'printf "%%s\\n" "$1" >>"%s"\n' "$2"
      printf 'exec "%s" "$@"\n' "$REAL_PYTHON"
    } >"$1/python3"
    chmod +x "$1/python3"
  }
  write_counting_shim "$CACHE_BIN" "$CACHE_LOG"

  # Launch with `<extra PATH prefix>` ahead of PATH and echo how many version
  # probes ran through the shim at `<log>` (default: the cache-case shim).
  cache_launch() {
    local prefix="${1:-$CACHE_BIN}" log="${2:-$CACHE_LOG}"
    : >"$log"
    rm -f "$FIXTURE_MARKER"
    HOME="$CACHE_HOME" PATH="$prefix:$PATH" \
      bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
    grep -cx -- '-c' "$log" || true
  }
  target_ran() {
    [[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped'
  }

  cold_calls="$(cache_launch)"
  assert_eq "a cold launch spends one version probe" "1" "$cold_calls"
  assert_eq "a cold launch runs the target" "ran" "$(target_ran)"
  warm_calls="$(cache_launch)"
  assert_eq "a warm launch spends no probe" "0" "$warm_calls"
  assert_eq "a warm launch still runs the target" "ran" "$(target_ran)"

  cache_record="$(find "$CACHE_HOME/.cache/disk-hygiene" -name 'interpreter-*' \
    -type f 2>/dev/null | head -n 1)"
  if [[ -z "$cache_record" ]]; then
    fail "no interpreter cache record was written"
  fi
  pass "the cache record is keyed per launcher directory, not a shared file"
  # `record_lookups`: the record's lookup lines, for hand-written records.
  record_lookups() { grep '^lookup=' "$cache_record"; }

  # The record stores the real interpreter the probe reported, not the shim it
  # ran through: the exec skips a trampoline hop.
  assert_eq "the record's interpreter is the probe's sys.executable" \
    "$("$REAL_PYTHON" -c 'import sys; print(sys.executable)' | tr -d '\r')" \
    "$(sed -n 's/^interpreter=//p' "$cache_record")"

  # A PATH that differs only in a directory holding no Python (fnm's per-shell
  # `fnm_multishells/<pid>_<ts>` entry) still resolves the same interpreter, so
  # it must hit the cache.
  FNM_DIR="$CACHE_ROOT/fnm_multishells/4242_1790000000000"
  mkdir -p "$FNM_DIR"
  printf '#!/usr/bin/env bash\n' >"$FNM_DIR/node"
  chmod +x "$FNM_DIR/node"
  fnm_calls="$(cache_launch "$CACHE_BIN:$FNM_DIR")"
  assert_eq "a PATH differing only in an fnm_multishells dir hits the cache" \
    "0" "$fnm_calls"
  assert_eq "and the target runs" "ran" "$(target_ran)"

  # A BASH_ENV that turns command hashing off must not blind the lookups: the
  # launcher turns hashing back on before it resolves anything.
  NOHASH_ENV="$CACHE_ROOT/nohash.bash"
  printf 'set +h\n' >"$NOHASH_ENV"
  cache_launch >/dev/null
  rm -f "$FIXTURE_MARKER"
  : >"$CACHE_LOG"
  HOME="$CACHE_HOME" PATH="$CACHE_BIN:$PATH" BASH_ENV="$NOHASH_ENV" \
    bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
  assert_eq "a BASH_ENV with hashing off still hits the cache" \
    "0" "$(grep -cx -- '-c' "$CACHE_LOG" || true)"
  assert_eq "and the target runs" "ran" "$(target_ran)"

  # A PATH on which a DIFFERENT python3 now wins must re-resolve.
  SHADOW_BIN="$CACHE_ROOT/shadow-bin"
  SHADOW_LOG="$CACHE_ROOT/shadow-calls"
  write_counting_shim "$SHADOW_BIN" "$SHADOW_LOG"
  cache_launch >/dev/null
  shadow_calls="$(cache_launch "$SHADOW_BIN:$CACHE_BIN" "$SHADOW_LOG")"
  assert_eq "a PATH on which another python3 wins re-resolves" "1" "$shadow_calls"
  assert_eq "the re-resolved record names the new lookup" "1" \
    "$(grep -c "^lookup=python3|$SHADOW_BIN/python3\$" "$cache_record")"

  # The python3 the record was resolved through is removed: a lookup that no
  # longer finds it re-resolves.
  cache_launch "$SHADOW_BIN:$CACHE_BIN" "$SHADOW_LOG" >/dev/null
  rm -f "$SHADOW_BIN/python3"
  removed_calls="$(cache_launch "$SHADOW_BIN:$CACHE_BIN")"
  assert_eq "a removed python3 lookup re-resolves" "1" "$removed_calls"
  assert_eq "and the target still runs" "ran" "$(target_ran)"

  # The cached interpreter itself is removed (a Python uninstalled under an
  # unchanged lookup): re-resolve rather than exec a missing file.
  cache_launch >/dev/null
  GONE_DIR="$CACHE_ROOT/gone"
  mkdir -p "$GONE_DIR"
  cp "$CACHE_BIN/python3" "$GONE_DIR/python3"
  {
    printf 'schema=2\n'
    printf 'written=%s\n' "$(date +%s)"
    printf 'interpreter=%s\n' "$GONE_DIR/python3"
    record_lookups
  } >"$cache_record.new"
  mv "$cache_record.new" "$cache_record"
  rm -f "$GONE_DIR/python3"
  gone_calls="$(cache_launch)"
  assert_eq "a removed cached interpreter re-resolves" "1" "$gone_calls"
  assert_eq "and the target still runs" "ran" "$(target_ran)"

  # An interpreter modified after the record was written is not the one that
  # was validated — the in-place-upgrade case. The lookup file counts too: a
  # trampoline rewritten to point elsewhere.
  cache_launch >/dev/null
  touch "$CACHE_BIN/python3"
  upgraded_calls="$(cache_launch)"
  assert_eq "a lookup newer than the record invalidates the cache" \
    "1" "$upgraded_calls"

  # A record from a future schema is not readable by this launcher.
  cache_launch >/dev/null
  printf 'schema=999\nwritten=1\ninterpreter=/nonexistent\n' >"$cache_record"
  schema_calls="$(cache_launch)"
  assert_eq "a foreign schema invalidates the cached interpreter" \
    "1" "$schema_calls"

  # An expired record is re-resolved rather than trusted. The staleness is
  # forged in the RECORD (an old `written=` epoch), not through an environment
  # override: the TTL is compiled in precisely so it cannot be widened by the
  # environment, and a test that reached for such a knob would be asserting a
  # channel this launcher deliberately does not have.
  # `write_record <written> <interpreter>`: a hand-written schema-2 record
  # carrying the current record's lookups, so only the named fields differ.
  write_record() {
    local lookups
    lookups="$(record_lookups)"
    printf 'schema=2\nwritten=%s\ninterpreter=%s\n%s\n' "$1" "$2" "$lookups" \
      >"$cache_record"
  }

  cache_launch >/dev/null
  write_record 1 "$(sed -n 's/^interpreter=//p' "$cache_record")"
  ttl_calls="$(cache_launch)"
  assert_eq "an expired record is re-resolved" "1" "$ttl_calls"

  # A corrupt record must fall back to full resolution — never to "no
  # interpreter", which is the guard's silent fail-open.
  cache_launch >/dev/null
  printf 'this is not a cache record\n' >"$cache_record"
  corrupt_calls="$(cache_launch)"
  assert_eq "a corrupt record falls back to resolution" "1" "$corrupt_calls"
  assert_eq "a corrupt record still runs the target" "ran" "$(target_ran)"

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
  IMPOSTOR_DIR="$CACHE_ROOT/impostor"
  mkdir -p "$IMPOSTOR_DIR"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$IMPOSTOR_DIR/node"
  chmod +x "$IMPOSTOR_DIR/node"
  write_record "$(date +%s)" "$IMPOSTOR_DIR/node"
  impostor_calls="$(cache_launch)"
  assert_eq "a record naming a non-interpreter basename is re-resolved" \
    "1" "$impostor_calls"
  assert_eq "and the target still runs under a real interpreter" "ran" "$(target_ran)"

  # A NATIVE WINDOWS interpreter path must be accepted from the cache.
  #
  # `sys.executable` on Windows is `C:\...\python.exe`, and it is what every
  # record stores. A basename check that split only on `/` left the whole
  # backslash path in place, the allowlist never matched, and the record was
  # rejected on EVERY invocation, silently and with no error. Nothing in the
  # previous contract set caught it, because every path this suite produced
  # was POSIX.
  if command -v cygpath >/dev/null 2>&1; then
    cache_launch >/dev/null
    write_record "$(date +%s)" "$(cygpath -w "$CACHE_BIN/python3")"
    native_calls="$(cache_launch)"
    assert_eq "a native Windows interpreter path is accepted from the cache" \
      "0" "$native_calls"
    assert_eq "and the target runs through it" "1" "$(grep -c . "$CACHE_LOG")"
    assert_eq "and the target ran" "ran" "$(target_ran)"
  else
    printf 'SKIP: no cygpath; native-path cache acceptance not exercised\n'
  fi

  # An interpreter under a non-ASCII directory must still resolve. The probe
  # reports `sys.executable` over a pipe; printed as text, Windows encodes it
  # with the ANSI code page, a character outside it (`碼` is not in cp1252)
  # raises, the probe exits non-zero, and every candidate is rejected: the
  # guard silently does not run. A venv gives an interpreter whose
  # `sys.executable` is its own path.
  UNICODE_ROOT="$CACHE_ROOT/ü碼 dir"
  if "$REAL_PYTHON" -m venv --without-pip "$UNICODE_ROOT/venv" >/dev/null 2>&1; then
    venv_python="$UNICODE_ROOT/venv/bin/python"
    [[ -x "$venv_python" ]] || venv_python="$UNICODE_ROOT/venv/Scripts/python.exe"
    UNICODE_BIN="$UNICODE_ROOT/bin"
    mkdir -p "$UNICODE_BIN"
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$venv_python" >"$UNICODE_BIN/python3"
    chmod +x "$UNICODE_BIN/python3"
    UNICODE_HOME="$CACHE_ROOT/home-unicode"
    mkdir -p "$UNICODE_HOME"
    rm -f "$FIXTURE_MARKER"
    HOME="$UNICODE_HOME" PATH="$UNICODE_BIN:$PATH" PYTHONUTF8=0 PYTHONIOENCODING='' \
      bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
    assert_eq "an interpreter under a non-ASCII directory runs the target" \
      "ran" "$(target_ran)"
    unicode_record="$(find "$UNICODE_HOME/.cache/disk-hygiene" -name 'interpreter-*' \
      -type f 2>/dev/null | head -n 1)"
    assert_contains "and the record names that interpreter" "ü碼 dir" \
      "$(sed -n 's/^interpreter=//p' "$unicode_record" 2>/dev/null)"
  else
    printf 'SKIP: no venv module; non-ASCII interpreter path not exercised\n'
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

  # `bash` runs the launcher directly, so no `env` process runs for the
  # shebang. Every row is checked, not just the first.
  assert_eq "every hooks.json row for $hook_name starts with bash" "0" \
    "$(jq --arg target "$hook_name" '[.hooks[][].hooks[] |
      select(.command | contains($target)) |
      select(.command | startswith("bash \"${CLAUDE_PLUGIN_ROOT}\"/") | not)] | length' "$HOOKS_JSON")"

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
# `py` belongs in the stub set with the other two: the launcher's third branch
# resolves through the Windows `py` launcher, and a host that has one resolves a
# real interpreter here, runs the monitor, and sees no systemMessage at all.
for stub in python3 python py; do
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

# --- the `py -3` branch validates the path it is handed ---
#
# `py` reports the interpreter it chose; a path that is not an interpreter by
# shape must be refused like any other, not exec'd.
PY_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN" "$PROBE_DIR" "$PY_BIN"' EXIT
for stub in python3 python; do
  printf '#!/usr/bin/env bash\nexit 127\n' >"$PY_BIN/$stub"
  chmod +x "$PY_BIN/$stub"
done
printf '#!/usr/bin/env bash\nexit 0\n' >"$PY_BIN/node"
chmod +x "$PY_BIN/node"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$PY_BIN/node" >"$PY_BIN/py"
chmod +x "$PY_BIN/py"
PY_OUT="$(
  HOME="$PY_BIN" PATH="$PY_BIN:$PATH" bash "$LAUNCHER" \
    "$SCRIPT_DIR/../skills/clean/scripts/guard_launch_monitor.py" \
    --data-root "$PY_BIN/data" 2>/dev/null || true
)"
assert_contains "a py -3 result that is not an interpreter is refused" \
  "systemMessage" "$PY_OUT"

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
  # half of a split line is excluded so a creation is counted once. The pattern
  # is POSIX ERE: strace writes `clone(`, `clone3(`, `fork(`, `vfork(`; a GNU
  # `\b` word boundary is not needed and is not portable.
  census_creations="$(grep -E '(clone3?|v?fork)\(' "$CENSUS_LOG" |
    grep -v unfinished | grep -cE '= [1-9][0-9]*$' || true)"
  census_execs="$(grep -E '^[0-9]+ +execve\(' "$CENSUS_LOG" |
    grep -cE '\) = 0$' || true)"
  assert_eq "a warm launch creates no process before exec (strace census)" \
    "0" "$census_creations"
  assert_eq "a warm launch execs exactly bash and the interpreter (strace census)" \
    "2" "$census_execs"
fi

# --- the per-session launch marker gates the Stop monitor before python ---
#
# `Stop` rows accept neither `matcher` nor `if`, so the only place a "did the
# guard run at all this session" gate can live is the launcher. The contract has
# five halves: a launch records the session (even when the launched python then
# dies, which is the very failure the monitor exists to report), a session
# unrecorded in a marker tree that EXISTS reaches no python at all, a recorded
# one runs exactly as before, a payload the launcher cannot key on falls back to
# running python, and a marker tree that does not exist at all falls back the
# same way rather than silencing the monitor.
MARKER_CASE="$PROBE_DIR/marker-case"
MARKER_ROOT_DIR="$MARKER_CASE/data"
MARKER_HOME="$MARKER_CASE/home"
MARKER_SEEN="$MARKER_CASE/target-stdin"
MARKER_DIR="$MARKER_ROOT_DIR/guard-launch-monitor"
mkdir -p "$MARKER_ROOT_DIR" "$MARKER_HOME" "$MARKER_CASE/tmp"
MARKER_TARGET="$FIXTURE_ROOT/skills/clean/scripts/marker_target.py"
{
  printf 'import pathlib, sys\n'
  # Byte-for-byte, through the binary buffer: the payload reaches python over a
  # here-string now, and a decoded round trip would hide a newline difference.
  printf 'pathlib.Path(sys.argv[1]).write_bytes(sys.stdin.buffer.read())\n'
  printf 'pathlib.Path(sys.argv[1] + ".argv").write_text("\\n".join(sys.argv[3:]))\n'
  printf 'raise SystemExit(int(sys.argv[2]))\n'
} >"$MARKER_TARGET"

MARKER_PAYLOAD=""
# Echo the launcher's exit code; `$MARKER_SEEN` exists afterwards only if the
# target actually started, and holds the bytes python read.
marker_launch() {
  local flag="$1" subdir="$2" target_rc="$3" rc=0
  rm -f "$MARKER_SEEN" "$MARKER_SEEN.argv"
  printf '%s' "$MARKER_PAYLOAD" |
    HOME="$MARKER_HOME" TMPDIR="$MARKER_CASE/tmp" \
      bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      --marker-root "$MARKER_ROOT_DIR" "$flag" "$subdir" \
      "$MARKER_TARGET" "$MARKER_SEEN" "$target_rc" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

marker_state() {
  [[ -f "$MARKER_DIR/$1.launched" ]] && printf 'present' || printf 'absent'
}

target_state() {
  [[ -e "$MARKER_SEEN" ]] && printf 'ran' || printf 'skipped'
}

MARKER_PAYLOAD='{"session_id":"sess-1","hook_event_name":"PreToolUse"}'
rm -rf "$MARKER_DIR"
marker_rc="$(marker_launch --launch-marker guard-launch-monitor 0)"
assert_eq "a guarded launch records the session" "present" "$(marker_state sess-1)"
assert_eq "a guarded launch still runs its target" "ran" "$(target_state)"
assert_eq "a guarded launch still reports its target's exit code" "0" "$marker_rc"
assert_eq "the marker flags never reach python's argv" "" "$(cat "$MARKER_SEEN.argv")"

# The monitor exists to catch a guard that launched and died, so a non-zero exit
# must leave the marker that keeps the monitor running for the rest of the turn.
rm -rf "$MARKER_DIR"
marker_rc="$(marker_launch --launch-marker guard-launch-monitor 3)"
assert_eq "a launch whose python exits non-zero still records the session" \
  "present" "$(marker_state sess-1)"
assert_eq "a launch whose python exits non-zero propagates that code" "3" "$marker_rc"

# An EXISTING marker tree that holds no marker for this session is the shape a
# launch-free session leaves, and is the only shape that may skip.
MARKER_PAYLOAD='{"session_id":"sess-1","hook_event_name":"Stop"}'
rm -rf "$MARKER_DIR"
mkdir -p "$MARKER_DIR"
marker_rc="$(marker_launch --skip-unless-marker guard-launch-monitor 0)"
assert_eq "an unrecorded session exits 0" "0" "$marker_rc"
assert_eq "an unrecorded session starts no python" "skipped" "$(target_state)"

# Not even a version probe: every interpreter name on PATH is a logging shim,
# and the cache HOME is empty, so any resolution attempt would leave a line.
SKIP_BIN="$MARKER_CASE/skip-bin"
SKIP_LOG="$MARKER_CASE/skip-calls"
mkdir -p "$SKIP_BIN"
: >"$SKIP_LOG"
for stub in python3 python py; do
  # shellcheck disable=SC2016  # `$0` is the stub's, deliberately unexpanded
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >>"%s"\nexit 127\n' "$SKIP_LOG" >"$SKIP_BIN/$stub"
  chmod +x "$SKIP_BIN/$stub"
done
printf '%s' "$MARKER_PAYLOAD" |
  HOME="$MARKER_CASE/skip-home" TMPDIR="$MARKER_CASE/tmp" PATH="$SKIP_BIN:$PATH" \
    bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    --marker-root "$MARKER_ROOT_DIR" --skip-unless-marker guard-launch-monitor \
    "$MARKER_TARGET" "$MARKER_SEEN" 0 >/dev/null 2>&1 || true
assert_eq "an unrecorded session spawns no interpreter, not even a probe" \
  "0" "$(grep -c . "$SKIP_LOG" || true)"

mkdir -p "$MARKER_DIR"
: >"$MARKER_DIR/sess-1.launched"
marker_rc="$(marker_launch --skip-unless-marker guard-launch-monitor 0)"
assert_eq "a recorded session runs python" "ran" "$(target_state)"
assert_eq "a recorded session exits 0" "0" "$marker_rc"

# Byte identity across the buffer-and-replay: python receives what it would have
# read from the inherited stdin, plus the newline `<<<` appends. Both consumers
# (`json.load(sys.stdin)`, `sys.stdin.read()` then `json.loads`) ignore it.
MARKER_EXPECTED="$MARKER_CASE/expected"
printf '%s\n' "$MARKER_PAYLOAD" >"$MARKER_EXPECTED"
assert_eq "the buffered payload reaches python unchanged" "same" \
  "$(cmp -s "$MARKER_EXPECTED" "$MARKER_SEEN" && printf 'same' || printf 'differs')"

# A payload the launcher cannot key on must behave exactly as it did before
# these flags existed: record nothing, skip nothing, run python.
MARKER_PAYLOAD='{"hook_event_name":"Stop","cwd":"/tmp"}'
rm -rf "$MARKER_DIR"
marker_rc="$(marker_launch --skip-unless-marker guard-launch-monitor 0)"
assert_eq "a payload with no session id still runs python" "ran" "$(target_state)"
assert_eq "a payload with no session id exits 0" "0" "$marker_rc"
marker_launch --launch-marker guard-launch-monitor 0 >/dev/null
assert_eq "a payload with no session id records nothing" "absent" \
  "$([[ -d "$MARKER_DIR" ]] && printf 'present' || printf 'absent')"

# A payload whose opening key is something else still keys correctly, through
# the unanchored fallback: the docs show `session_id` first for every event but
# guarantee no ordering, and a reordered payload must degrade to running python,
# not to keying on nothing.
MARKER_PAYLOAD='{"hook_event_name":"Stop","session_id":"sess-2"}'
rm -rf "$MARKER_DIR"
mkdir -p "$MARKER_DIR"
marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
assert_eq "a reordered payload still keys on its session id" "skipped" "$(target_state)"
mkdir -p "$MARKER_DIR"
: >"$MARKER_DIR/sess-2.launched"
marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
assert_eq "a reordered payload finds its own marker" "ran" "$(target_state)"

# --- a launch that can write no marker at all must not silence the monitor ---
#
# Both candidates fail on the launch side here, which leaves the Stop row
# nothing to find. Reading only the marker FILE would then skip every Stop for
# the rest of the session: a silent failure in the one detector that exists to
# report silent failures. The Stop row therefore skips only when a candidate
# DIRECTORY exists, and otherwise runs the monitor as it did before the flags.
#
# "Unwritable" is staged structurally rather than through permission bits, which
# MSYS cannot set against Windows ACLs: `mkdir -p` refuses a parent that is a
# regular FILE on every host, and refuses a target that already exists as one.
# The marker root sits under a file; `TMPDIR` itself stays a real directory
# (bash may place a here-string there) with a file occupying the name the tmp
# fallback wants.
BLOCKED_CASE="$PROBE_DIR/blocked-case"
BLOCKED_TMP="$BLOCKED_CASE/tmp"
mkdir -p "$BLOCKED_CASE" "$BLOCKED_TMP"
BLOCKED_FILE="$BLOCKED_CASE/not-a-directory"
: >"$BLOCKED_FILE"
: >"$BLOCKED_TMP/disk-hygiene-guard-launch-monitor"
BLOCKED_ROOT="$BLOCKED_FILE/data"

blocked_launch() {
  local flag="$1" subdir="$2" rc=0
  rm -f "$MARKER_SEEN" "$MARKER_SEEN.argv"
  printf '%s' "$MARKER_PAYLOAD" |
    HOME="$MARKER_HOME" TMPDIR="$BLOCKED_TMP" \
      bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      --marker-root "$BLOCKED_ROOT" "$flag" "$subdir" \
      "$MARKER_TARGET" "$MARKER_SEEN" 0 >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

MARKER_PAYLOAD='{"session_id":"sess-3","hook_event_name":"PreToolUse"}'
blocked_rc="$(blocked_launch --launch-marker guard-launch-monitor)"
assert_eq "a launch that can write no marker still runs its target" \
  "ran" "$(target_state)"
assert_eq "a launch that can write no marker reports its target's code" \
  "0" "$blocked_rc"
assert_eq "a failed marker write creates no candidate directory" "absent" \
  "$([[ -d "$BLOCKED_ROOT" || -d "$BLOCKED_TMP/disk-hygiene-guard-launch-monitor" ]] &&
    printf 'present' || printf 'absent')"
assert_eq "and it leaves the blocking file alone" "file" \
  "$([[ -f "$BLOCKED_FILE" ]] && printf 'file' || printf 'gone')"

MARKER_PAYLOAD='{"session_id":"sess-3","hook_event_name":"Stop"}'
blocked_rc="$(blocked_launch --skip-unless-marker guard-launch-monitor)"
assert_eq "a Stop with no candidate marker directory runs the monitor" \
  "ran" "$(target_state)"
assert_eq "a Stop with no candidate marker directory exits 0" "0" "$blocked_rc"

# --- both wirings carry the flag the other one depends on ---
guard_rows="$(jq '[.hooks.PreToolUse[].hooks[] |
  select(.command | contains("destructive_guard.py"))] | length' "$HOOKS_JSON")"
guard_marked="$(jq '[.hooks.PreToolUse[].hooks[] |
  select(.command | contains("destructive_guard.py")) |
  select(.command | contains("--launch-marker guard-launch-monitor"))] | length' \
  "$HOOKS_JSON")"
assert_eq "every engine-gate row records the session it launched in" \
  "$guard_rows" "$guard_marked"
assert_eq "the Stop row skips a session that launched no guard" "1" \
  "$(jq '[.hooks.Stop[].hooks[] |
    select(.command | contains("--skip-unless-marker guard-launch-monitor"))] | length' \
    "$HOOKS_JSON")"

pass "all run-python-hook contract checks"
