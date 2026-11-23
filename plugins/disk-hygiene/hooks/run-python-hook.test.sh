#!/usr/bin/env bash
# test-scope: plugins/disk-hygiene/hooks/hooks.json plugins/disk-hygiene/prerequisites.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="$SCRIPT_DIR/run-python-hook.sh"
ENGINE="$SCRIPT_DIR/../skills/clean/scripts/hygiene.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi
if ! grep -q "\"min\": \"$FLOOR\"" "$SCRIPT_DIR/../prerequisites.json"; then
  echo "FAIL: prerequisites.json does not declare MIN_PYTHON $FLOOR" >&2
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

SED_REAL="$(command -v sed)"
PROBE_DIR="$(mktemp -d)"
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
  --mode engine-gate </dev/null >/dev/null 2>&1 || true

engine_reads=0
for call in "$PROBE_CALLS"/call-*; do
  [[ -e "$call" ]] || continue
  engine_reads=$((engine_reads + 1))
done
assert_eq "the launcher never sed-reads the engine" "0" "$engine_reads"

FIXTURE_ROOT="$PROBE_DIR/plugin"
mkdir -p "$FIXTURE_ROOT/hooks" "$FIXTURE_ROOT/skills/clean/scripts"
cp "$LAUNCHER" "$FIXTURE_ROOT/hooks/run-python-hook.sh"
FIXTURE_TARGET="$FIXTURE_ROOT/skills/clean/scripts/destructive_guard.py"
FIXTURE_MARKER="$PROBE_DIR/target-ran"
printf 'import pathlib, sys\npathlib.Path(sys.argv[1]).write_text("ran")\n' \
  >"$FIXTURE_TARGET"

write_fixture_engine() {
  {
    printf '%s\n' '"""Fixture engine for the version-floor contract."""'
    printf 'MIN_PYTHON = (%s, %s)\n' "$1" "$2"
    printf '%s\n' 'FILLER = 0'
    printf '%s\n' 'MIN_PYTHON = (9, 99)'
  } >"$FIXTURE_ROOT/skills/clean/scripts/hygiene.py"
}

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

rm -f "$FIXTURE_MARKER"
cp "$SCRIPT_DIR/../skills/clean/scripts/hygiene.py" \
  "$FIXTURE_ROOT/skills/clean/scripts/hygiene.py"
FIXTURE_REAL_HOME="$PROBE_DIR/home-real"
mkdir -p "$FIXTURE_REAL_HOME"
HOME="$FIXTURE_REAL_HOME" bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
  "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
assert_eq "the engine's real floor still admits this host's interpreter" \
  "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"

CACHE_ROOT="$PROBE_DIR/cache-case"
CACHE_BIN="$CACHE_ROOT/bin"
CACHE_HOME="$CACHE_ROOT/home"
CACHE_LOG="$CACHE_ROOT/python-calls"
mkdir -p "$CACHE_BIN" "$CACHE_HOME"
REAL_PYTHON="$(command -v python3 || true)"
if [[ -z "$REAL_PYTHON" ]]; then
  printf 'SKIP: no python3 on PATH; cache contract not exercised\n'
else
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
  record_lookups() { grep '^lookup=' "$cache_record"; }

  assert_eq "the record's interpreter is the probe's sys.executable" \
    "$("$REAL_PYTHON" -c 'import sys; print(sys.executable)' | tr -d '\r')" \
    "$(sed -n 's/^interpreter=//p' "$cache_record")"

  FNM_DIR="$CACHE_ROOT/fnm_multishells/4242_1790000000000"
  mkdir -p "$FNM_DIR"
  printf '#!/usr/bin/env bash\n' >"$FNM_DIR/node"
  chmod +x "$FNM_DIR/node"
  fnm_calls="$(cache_launch "$CACHE_BIN:$FNM_DIR")"
  assert_eq "a PATH differing only in an fnm_multishells dir hits the cache" \
    "0" "$fnm_calls"
  assert_eq "and the target runs" "ran" "$(target_ran)"

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

  SHADOW_BIN="$CACHE_ROOT/shadow-bin"
  SHADOW_LOG="$CACHE_ROOT/shadow-calls"
  write_counting_shim "$SHADOW_BIN" "$SHADOW_LOG"
  cache_launch >/dev/null
  shadow_calls="$(cache_launch "$SHADOW_BIN:$CACHE_BIN" "$SHADOW_LOG")"
  assert_eq "a PATH on which another python3 wins re-resolves" "1" "$shadow_calls"
  assert_eq "the re-resolved record names the new lookup" "1" \
    "$(grep -c "^lookup=python3|$SHADOW_BIN/python3\$" "$cache_record")"

  cache_launch "$SHADOW_BIN:$CACHE_BIN" "$SHADOW_LOG" >/dev/null
  rm -f "$SHADOW_BIN/python3"
  removed_calls="$(cache_launch "$SHADOW_BIN:$CACHE_BIN")"
  assert_eq "a removed python3 lookup re-resolves" "1" "$removed_calls"
  assert_eq "and the target still runs" "ran" "$(target_ran)"

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

  cache_launch >/dev/null
  touch "$CACHE_BIN/python3"
  upgraded_calls="$(cache_launch)"
  assert_eq "a lookup newer than the record invalidates the cache" \
    "1" "$upgraded_calls"

  cache_launch >/dev/null
  printf 'schema=999\nwritten=1\ninterpreter=/nonexistent\n' >"$cache_record"
  schema_calls="$(cache_launch)"
  assert_eq "a foreign schema invalidates the cached interpreter" \
    "1" "$schema_calls"

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

  cache_launch >/dev/null
  printf 'this is not a cache record\n' >"$cache_record"
  corrupt_calls="$(cache_launch)"
  assert_eq "a corrupt record falls back to resolution" "1" "$corrupt_calls"
  assert_eq "a corrupt record still runs the target" "ran" "$(target_ran)"

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

  NOCACHE_HOME="$CACHE_ROOT/home-readonly"
  mkdir -p "$NOCACHE_HOME"
  rm -f "$FIXTURE_MARKER"
  HOME="$NOCACHE_HOME/does-not-exist" PATH="$CACHE_BIN:$PATH" \
    bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
  assert_eq "an unusable cache location still runs the target" \
    "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"
fi

HOOKS_JSON="$SCRIPT_DIR/hooks.json"
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required" >&2
  exit 0
fi

for hook_name in destructive_guard.py guard_launch_monitor.py engine_context.py; do
  entry="$(jq -c --arg target "$hook_name" '
    .hooks | to_entries[] | .value[]? | .hooks[]? |
    select((.args // []) | map(tostring) | join(" ") | contains($target))
  ' "$HOOKS_JSON" | head -n1)"
  if [[ -z "$entry" ]]; then
    fail "hooks.json has no command hook referencing $hook_name"
  fi

  argv="$(jq -r '[.command] + (.args // []) | join(" ")' <<<"$entry")"
  assert_contains "hooks.json command for $hook_name invokes the launcher" \
    "run-python-hook.sh" "$argv"
  assert_contains "hooks.json command for $hook_name names exec-bash.mjs" \
    "exec-bash.mjs" "$argv"

  assert_eq "every hooks.json row for $hook_name is node exec form" "0" \
    "$(jq --arg target "$hook_name" --arg launcher '${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs' '
      [.hooks[][].hooks[] |
        select((.args // []) | map(tostring) | join(" ") | contains($target)) |
        select(
          .command != "node" or
          ((.args // [])[0] != $launcher) or
          (((.args // []) | map(tostring) | join(" ")) | contains("run-python-hook.sh") | not)
        )] | length' "$HOOKS_JSON")"

  bad_cmd="$(jq -r --arg target "$hook_name" '
    [.hooks[][].hooks[] |
      select((.args // []) | map(tostring) | join(" ") | contains($target)) |
      select(.command != "node") | .command] | length' "$HOOKS_JSON")"
  assert_eq "hooks.json entry for $hook_name does not use a shell command" "0" "$bad_cmd"
  pass "hooks.json command for $hook_name is node exec form"
done

FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN" "$PROBE_DIR"' EXIT
for stub in python3 python py; do
  printf '#!/usr/bin/env bash\nexit 127\n' >"$FAKE_BIN/$stub"
  chmod +x "$FAKE_BIN/$stub"
done

MONITOR_OUT="$(
  PATH="$FAKE_BIN:$PATH" bash "$LAUNCHER" \
    "$SCRIPT_DIR/../skills/clean/scripts/guard_launch_monitor.py" \
    --data-root /tmp/disk-hygiene-test </dev/null 2>/dev/null || true
)"
assert_contains "monitor mode warns when python is unavailable" "systemMessage" "$MONITOR_OUT"
assert_contains "monitor mode names the missing interpreter" "no usable Python 3" "$MONITOR_OUT"
assert_eq "monitor mode's no-interpreter output is valid JSON" "true" \
  "$(jq -e 'has("systemMessage")' <<<"$MONITOR_OUT" 2>/dev/null || echo false)"

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

NOPY_DIR="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN" "$PROBE_DIR" "$PY_BIN" "$NOPY_DIR"' EXIT
GUARD="$SCRIPT_DIR/../skills/clean/scripts/destructive_guard.py"

nopy_guard() {
  local payload="$1"
  shift
  NOPY_RC=0
  TMPDIR="$NOPY_DIR/tmp" PATH="$FAKE_BIN:$PATH" bash "$LAUNCHER" "$@" \
    <<<"$payload" >"$NOPY_DIR/out" 2>"$NOPY_DIR/err" || NOPY_RC=$?
  NOPY_OUT="$(<"$NOPY_DIR/out")"
  NOPY_ERR="$(<"$NOPY_DIR/err")"
}
mkdir -p "$NOPY_DIR/tmp" "$NOPY_DIR/data"

engine_payload='{"session_id":"s-engine","tool_name":"Bash","tool_input":{"command":"python3 /p/skills/clean/scripts/hygiene.py apply --token x"}}'
nopy_guard "$engine_payload" --marker-root "$NOPY_DIR/data" --launch-marker guard-launch-monitor \
  "$GUARD" --mode engine-gate
assert_eq "engine-gate without python denies a command naming the engine" "2" "$NOPY_RC"
assert_contains "the engine deny names the missing interpreter" "no usable Python 3" "$NOPY_ERR"
assert_contains "the engine deny names the remedy" "lib/prerequisites.mjs' check" "$NOPY_ERR"
assert_eq "the engine deny prints no allow-shaped stdout" "" "$NOPY_OUT"

# shellcheck disable=SC2016  # a literal PowerShell variable, deliberately unexpanded
upper_payload='{"session_id":"s-upper","tool_name":"PowerShell","tool_input":{"command":"& $py C:\\p\\HYGIENE.PY scan ."}}'
nopy_guard "$upper_payload" "$GUARD" --mode=engine-gate
assert_eq "engine-gate without python matches the engine case-insensitively" "2" "$NOPY_RC"

nopy_guard "" "$GUARD" --mode engine-gate
assert_eq "engine-gate without python denies when no payload was seen" "2" "$NOPY_RC"

# shellcheck disable=SC2016  # a literal PowerShell variable, deliberately unexpanded
plain_payload='{"session_id":"s-plain","tool_name":"PowerShell","tool_input":{"command":"& $tool --version"}}'
nopy_guard "$plain_payload" --marker-root "$NOPY_DIR/data" --launch-marker guard-launch-monitor \
  "$GUARD" --mode engine-gate
assert_eq "engine-gate without python lets a marker-free command proceed" "0" "$NOPY_RC"
assert_eq "the marker-free proceed carries a systemMessage" "true" \
  "$(jq -e '.systemMessage | test("no usable Python 3")' <<<"$NOPY_OUT" 2>/dev/null || echo false)"
assert_eq "the marker-free proceed carries no hookSpecificOutput" "false" \
  "$(jq -r 'has("hookSpecificOutput")' <<<"$NOPY_OUT" 2>/dev/null)"
nopy_guard "$plain_payload" --marker-root "$NOPY_DIR/data" --launch-marker guard-launch-monitor \
  "$GUARD" --mode engine-gate
assert_eq "the marker-free notice is once per session: rc" "0" "$NOPY_RC"
assert_eq "the marker-free notice is once per session: silent after the first" "" "$NOPY_OUT"
nopy_guard "${plain_payload/s-plain/s-other}" --marker-root "$NOPY_DIR/data" \
  --launch-marker guard-launch-monitor "$GUARD" --mode engine-gate
assert_contains "a new session gets its own notice" "systemMessage" "$NOPY_OUT"

MONITOR="$SCRIPT_DIR/../skills/clean/scripts/guard_launch_monitor.py"
nopy_guard "$plain_payload" --marker-root "$NOPY_DIR/data" "$MONITOR" --data-root "$NOPY_DIR/data"
assert_eq "the task-end notice stays quiet after the guard's notice" "" "$NOPY_OUT"
stop_payload='{"session_id":"s-stop","hook_event_name":"Stop"}'
nopy_guard "$stop_payload" --marker-root "$NOPY_DIR/data" "$MONITOR" --data-root "$NOPY_DIR/data"
assert_contains "the first task end of a session gets the notice" "no usable Python 3" "$NOPY_OUT"
nopy_guard "$stop_payload" --marker-root "$NOPY_DIR/data" "$MONITOR" --data-root "$NOPY_DIR/data"
assert_eq "a second task end in the same session stays quiet" "" "$NOPY_OUT"

nopy_guard '{"tool_name":"PowerShell","tool_input":{"command":"Get-ChildItem"}}' \
  "$GUARD" --mode engine-gate
assert_contains "a payload with no session id re-notices rather than going silent" \
  "systemMessage" "$NOPY_OUT"

planted_notice() {
  NOPY_RC=0
  TMPDIR="$1" PATH="$FAKE_BIN:$PATH" bash "$LAUNCHER" "$GUARD" --mode engine-gate \
    <<<"$2" >"$NOPY_DIR/out" 2>"$NOPY_DIR/err" || NOPY_RC=$?
  NOPY_OUT="$(<"$NOPY_DIR/out")"
}
planted_payload='{"session_id":"s-planted","tool_name":"PowerShell","tool_input":{"command":"Get-ChildItem"}}'
mkdir -p "$NOPY_DIR/link-tmp" "$NOPY_DIR/elsewhere"
: >"$NOPY_DIR/elsewhere/s-planted.noticed"
ln -s "$NOPY_DIR/elsewhere" "$NOPY_DIR/link-tmp/disk-hygiene-guard-no-interpreter"
planted_notice "$NOPY_DIR/link-tmp" "$planted_payload"
assert_contains "a symlinked marker directory holding this session's marker is not trusted" \
  "systemMessage" "$NOPY_OUT"
planted_notice "$NOPY_DIR/link-tmp" "${planted_payload/s-planted/s-through-link}"
assert_eq "no marker is written through a symlinked marker directory" "false" \
  "$([[ -e "$NOPY_DIR/elsewhere/s-through-link.noticed" ]] && echo true || echo false)"
planted_notice "$NOPY_DIR/link-tmp" "$planted_payload"
assert_contains "a symlinked marker directory never latches the notice" "systemMessage" "$NOPY_OUT"

if [[ "$(id -u)" == 0 ]] && id nobody >/dev/null 2>&1; then
  mkdir -p "$NOPY_DIR/foreign-tmp/disk-hygiene-guard-no-interpreter"
  : >"$NOPY_DIR/foreign-tmp/disk-hygiene-guard-no-interpreter/s-planted.noticed"
  chown -R nobody "$NOPY_DIR/foreign-tmp/disk-hygiene-guard-no-interpreter"
  planted_notice "$NOPY_DIR/foreign-tmp" "$planted_payload"
  assert_contains "a marker directory another user owns is not trusted" "systemMessage" "$NOPY_OUT"
else
  printf 'SKIP: %s\n' "a marker directory another user owns (needs root to create one)"
fi

mkdir -p "$NOPY_DIR/own-tmp"
planted_notice "$NOPY_DIR/own-tmp" "$planted_payload"
assert_contains "the first call in a session with an own tmp marker directory notices" \
  "systemMessage" "$NOPY_OUT"
planted_notice "$NOPY_DIR/own-tmp" "$planted_payload"
assert_eq "an own tmp marker directory latches the notice once per session" "" "$NOPY_OUT"

nopy_guard "$plain_payload" "$GUARD" --plugin-root /p
assert_eq "belt mode without python denies even a marker-free command" "2" "$NOPY_RC"
assert_contains "the belt deny names the missing interpreter" "no usable Python 3" "$NOPY_ERR"
nopy_guard "$plain_payload" "$GUARD" --mode belt
assert_eq "an explicit belt mode without python denies" "2" "$NOPY_RC"
nopy_guard "$plain_payload" "$GUARD" --mode bogus
assert_eq "an unrecognized mode without python denies, as resolve_mode falls back to belt" "2" "$NOPY_RC"

HOOKS_JSON="$SCRIPT_DIR/hooks.json"
run_registered_args() {
  local payload="$1" args_json="$2" arg substituted=()
  while IFS= read -r arg; do
    arg="${arg//\$\{CLAUDE_PLUGIN_ROOT\}/$SCRIPT_DIR/..}"
    arg="${arg//\$\{CLAUDE_PLUGIN_DATA\}/$NOPY_DIR/data}"
    substituted+=("$arg")
  done < <(jq -r '.[]' <<<"$args_json")
  nopy_guard "$payload" "${substituted[@]:2}"
}
while IFS= read -r args_json; do
  run_registered_args "$engine_payload" "$args_json"
  assert_eq "registered engine-gate row denies an engine command without python" "2" "$NOPY_RC"
done < <(jq -c '.hooks.PreToolUse[].hooks[] | .args |
  select(map(tostring) | join(" ") | contains("destructive_guard.py"))' "$HOOKS_JSON")
belt_args="$(sed -n 's/^ *args: *//p' \
  "$SCRIPT_DIR/../skills/clean/SKILL.md" | head -n 1)"
belt_args="${belt_args#\'}"
belt_args="${belt_args%\'}"
[[ -n "$belt_args" ]] || fail "could not read the belt registration from SKILL.md"
run_registered_args "$plain_payload" "$belt_args"
assert_eq "the registered belt row denies without python" "2" "$NOPY_RC"

CONTEXT_OUT="$(
  PATH="$FAKE_BIN:$PATH" bash "$LAUNCHER" \
    "$SCRIPT_DIR/../skills/clean/scripts/engine_context.py" --plugin-root /p \
    </dev/null 2>/dev/null || true
)"
assert_eq "the clean expansion is blocked without python" "block" \
  "$(jq -r '.decision // ""' <<<"$CONTEXT_OUT" 2>/dev/null)"
assert_contains "the expansion block names the remedy" "lib/prerequisites.mjs' check" \
  "$(jq -r '.reason // ""' <<<"$CONTEXT_OUT" 2>/dev/null)"

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
  HOME="$CENSUS_HOME" bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
  rm -f "$FIXTURE_MARKER"
  HOME="$CENSUS_HOME" strace -f -qq -e trace=clone,clone3,fork,vfork,execve \
    -o "$CENSUS_LOG" bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    "$FIXTURE_TARGET" "$FIXTURE_MARKER" >/dev/null 2>&1 || true
  assert_eq "the traced warm launch still runs the target" \
    "ran" "$([[ -e "$FIXTURE_MARKER" ]] && printf 'ran' || printf 'skipped')"
  census_creations="$(grep -E '(clone3?|v?fork)\(' "$CENSUS_LOG" |
    grep -v unfinished | grep -cE '= [1-9][0-9]*$' || true)"
  census_execs="$(grep -E '^[0-9]+ +execve\(' "$CENSUS_LOG" |
    grep -cE '\) = 0$' || true)"
  assert_eq "a warm launch creates no process before exec (strace census)" \
    "0" "$census_creations"
  assert_eq "a warm launch execs exactly bash and the interpreter (strace census)" \
    "2" "$census_execs"
fi

MARKER_CASE="$PROBE_DIR/marker-case"
MARKER_ROOT_DIR="$MARKER_CASE/data"
MARKER_HOME="$MARKER_CASE/home"
MARKER_SEEN="$MARKER_CASE/target-stdin"
MARKER_DIR="$MARKER_ROOT_DIR/guard-launch-monitor"
mkdir -p "$MARKER_ROOT_DIR" "$MARKER_HOME" "$MARKER_CASE/tmp"
MARKER_TARGET="$FIXTURE_ROOT/skills/clean/scripts/marker_target.py"
{
  printf 'import pathlib, sys\n'
  printf 'pathlib.Path(sys.argv[1]).write_bytes(sys.stdin.buffer.read())\n'
  printf 'pathlib.Path(sys.argv[1] + ".argv").write_text("\\n".join(sys.argv[3:]))\n'
  printf 'raise SystemExit(int(sys.argv[2]))\n'
} >"$MARKER_TARGET"

MARKER_PAYLOAD=""
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

rm -rf "$MARKER_DIR"
marker_rc="$(marker_launch --launch-marker guard-launch-monitor 3)"
assert_eq "a launch whose python exits non-zero still records the session" \
  "present" "$(marker_state sess-1)"
assert_eq "a launch whose python exits non-zero propagates that code" "3" "$marker_rc"

MARKER_PAYLOAD='{"session_id":"sess-1","hook_event_name":"Stop"}'
rm -rf "$MARKER_DIR"
mkdir -p "$MARKER_DIR"
marker_rc="$(marker_launch --skip-unless-marker guard-launch-monitor 0)"
assert_eq "an unrecorded session exits 0" "0" "$marker_rc"
assert_eq "an unrecorded session starts no python" "skipped" "$(target_state)"

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

skill_launch() {
  local payload="$1" rc=0
  : >"$SKIP_LOG"
  SKILL_OUT="$(printf '%s' "$payload" |
    HOME="$MARKER_CASE/skip-home" TMPDIR="$MARKER_CASE/tmp" PATH="$SKIP_BIN:$PATH" \
      bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      --marker-root "$MARKER_ROOT_DIR" --launch-marker clean-invoked \
      --only-skill disk-hygiene:clean 2>&1)" || rc=$?
  SKILL_RC="$rc"
}
skill_marker() {
  [[ -f "$MARKER_ROOT_DIR/clean-invoked/$1.launched" ]] && printf 'present' || printf 'absent'
}
skill_launch '{"session_id":"sk-1","tool_name":"Skill","tool_input":{"skill":"disk-hygiene:clean","args":"/tmp/x"}}'
assert_eq "a model load of clean records the session" "present" "$(skill_marker sk-1)"
assert_eq "the marker-only row exits 0" "0" "$SKILL_RC"
assert_eq "the marker-only row prints nothing, so it makes no permission decision" "" "$SKILL_OUT"
assert_eq "the marker-only row spawns no interpreter" "0" "$(grep -c . "$SKIP_LOG" || true)"
skill_launch '{"session_id":"sk-2","tool_name":"Skill","tool_input":{"skill":"/disk-hygiene:clean"}}'
assert_eq "a leading slash on the skill name still records" "present" "$(skill_marker sk-2)"
for other in \
  '{"session_id":"sk-3","tool_name":"Skill","tool_input":{"skill":"repo-hygiene:clean"}}' \
  '{"session_id":"sk-3","tool_name":"Skill","tool_input":{"skill":"clean"}}' \
  '{"session_id":"sk-3","tool_name":"Skill","tool_input":{"skill":"disk-hygiene:clean-x"}}' \
  '{"session_id":"sk-3","tool_name":"Skill","tool_input":{"skill":"disk-hygiene:audit","args":"{\"skill\":\"disk-hygiene:clean\"}"}}'; do
  skill_launch "$other"
  assert_eq "another skill records nothing: $other" "absent" "$(skill_marker sk-3)"
  assert_eq "another skill exits 0 silently: $other" "0:" "$SKILL_RC:$SKILL_OUT"
done

mkdir -p "$MARKER_DIR"
: >"$MARKER_DIR/sess-1.launched"
marker_rc="$(marker_launch --skip-unless-marker guard-launch-monitor 0)"
assert_eq "a recorded session runs python" "ran" "$(target_state)"
assert_eq "a recorded session exits 0" "0" "$marker_rc"

MARKER_EXPECTED="$MARKER_CASE/expected"
printf '%s\n' "$MARKER_PAYLOAD" >"$MARKER_EXPECTED"
assert_eq "the buffered payload reaches python unchanged" "same" \
  "$(cmp -s "$MARKER_EXPECTED" "$MARKER_SEEN" && printf 'same' || printf 'differs')"

MARKER_PAYLOAD='{"hook_event_name":"Stop","cwd":"/tmp"}'
rm -rf "$MARKER_DIR"
marker_rc="$(marker_launch --skip-unless-marker guard-launch-monitor 0)"
assert_eq "a payload with no session id still runs python" "ran" "$(target_state)"
assert_eq "a payload with no session id exits 0" "0" "$marker_rc"
marker_launch --launch-marker guard-launch-monitor 0 >/dev/null
assert_eq "a payload with no session id records nothing" "absent" \
  "$([[ -d "$MARKER_DIR" ]] && printf 'present' || printf 'absent')"

MARKER_PAYLOAD='{"hook_event_name":"Stop","session_id":"sess-2"}'
rm -rf "$MARKER_DIR"
mkdir -p "$MARKER_DIR"
marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
assert_eq "a reordered payload still keys on its session id" "skipped" "$(target_state)"
mkdir -p "$MARKER_DIR"
: >"$MARKER_DIR/sess-2.launched"
marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
assert_eq "a reordered payload finds its own marker" "ran" "$(target_state)"

present_or_absent() { [[ -e "$1" || -L "$1" ]] && printf 'present' || printf 'absent'; }
OLD_TOKEN=$'1790000000-4242-17\n'
MARKER_PAYLOAD='{"session_id":"sess-7","hook_event_name":"PreToolUse"}'
rm -rf "$MARKER_DIR"
mkdir -p "$MARKER_DIR"
printf '%s' "$OLD_TOKEN" >"$MARKER_DIR/sess-7.seen"
marker_launch --launch-marker guard-launch-monitor 0 >/dev/null
launch_token="$(<"$MARKER_DIR/sess-7.launched")"
assert_eq "a launch writes a token of epoch seconds, PID and RANDOM" "token" \
  "$([[ "$launch_token" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]] && printf 'token' || printf '%s' "$launch_token")"
assert_eq "a launch removes the monitor's .seen" "absent" "$(present_or_absent "$MARKER_DIR/sess-7.seen")"
marker_launch --launch-marker guard-launch-monitor 0 >/dev/null
assert_eq "each launch writes its own token" "differs" \
  "$([[ "$(<"$MARKER_DIR/sess-7.launched")" != "$launch_token" ]] && printf 'differs' || printf 'same')"

MARKER_PAYLOAD='{"session_id":"sess-7","hook_event_name":"Stop"}'
cp "$MARKER_DIR/sess-7.launched" "$MARKER_DIR/sess-7.seen"
marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
assert_eq "a launch the monitor has seen skips the Stop" "skipped" "$(target_state)"

seen_state_runs() {
  rm -rf "$MARKER_DIR/sess-7.launched" "$MARKER_DIR/sess-7.seen"
  printf '%s' "$2" >"$MARKER_DIR/sess-7.launched"
  [[ "$3" == - ]] || printf '%s' "$3" >"$MARKER_DIR/sess-7.seen"
  marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
  assert_eq "$1" "ran" "$(target_state)"
}
seen_state_runs "a launch since .seen runs the monitor" "$OLD_TOKEN" $'1790000061-4243-18\n'
seen_state_runs "a missing .seen runs the monitor" "$OLD_TOKEN" -
seen_state_runs "an empty .launched runs the monitor" '' ''
seen_state_runs "a malformed .launched runs the monitor" $'garbage\n' $'garbage\n'
seen_state_runs "a .launched with a second line runs the monitor" $'1-2-3\nx' $'1-2-3\nx'
rm -f "$MARKER_DIR/sess-7.seen"
printf '%s' "$OLD_TOKEN" >"$MARKER_DIR/sess-7.launched"
mkdir "$MARKER_DIR/sess-7.seen"
marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
assert_eq "a .seen that is no file runs the monitor" "ran" "$(target_state)"
rmdir "$MARKER_DIR/sess-7.seen"
# Root reads every file, and MSYS cannot set these bits against Windows ACLs.
if [[ "$(id -u)" != 0 && "${OSTYPE:-}" != msys* && "${OSTYPE:-}" != cygwin* ]]; then
  printf '%s' "$OLD_TOKEN" >"$MARKER_DIR/sess-7.launched"
  printf '%s' "$OLD_TOKEN" >"$MARKER_DIR/sess-7.seen"
  chmod 000 "$MARKER_DIR/sess-7.seen"
  marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
  assert_eq "an unreadable .seen runs the monitor" "ran" "$(target_state)"
  chmod 600 "$MARKER_DIR/sess-7.seen"
  chmod 000 "$MARKER_DIR/sess-7.launched"
  marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
  assert_eq "an unreadable .launched runs the monitor" "ran" "$(target_state)"
  chmod 600 "$MARKER_DIR/sess-7.launched"

  MARKER_PAYLOAD='{"session_id":"sess-7","hook_event_name":"PreToolUse"}'
  chmod 444 "$MARKER_DIR/sess-7.launched"
  marker_launch --launch-marker guard-launch-monitor 0 >/dev/null
  assert_eq "a launch whose open fails has already removed .seen" "absent" \
    "$(present_or_absent "$MARKER_DIR/sess-7.seen")"
  chmod 600 "$MARKER_DIR/sess-7.launched"
  MARKER_PAYLOAD='{"session_id":"sess-7","hook_event_name":"Stop"}'
  marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
  assert_eq "and the next Stop runs the monitor" "ran" "$(target_state)"
else
  printf 'SKIP: %s\n' "markers unreadable or unwritable by permission bits (needs a non-root POSIX user)"
fi

FAILING_WRITE_ENV="$MARKER_CASE/failing-token-write.bash"
cat >"$FAILING_WRITE_ENV" <<'ENV'
printf() {
  if [[ $# -eq 2 && "$1" == '%s\n' && "$2" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]]; then
    return 1
  fi
  builtin printf "$@"
}
ENV
printf '%s' "$OLD_TOKEN" >"$MARKER_DIR/sess-8.launched"
printf '%s' "$OLD_TOKEN" >"$MARKER_DIR/sess-8.seen"
printf '%s' '{"session_id":"sess-8","hook_event_name":"PreToolUse"}' |
  HOME="$MARKER_HOME" TMPDIR="$MARKER_CASE/tmp" BASH_ENV="$FAILING_WRITE_ENV" \
    bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
    --marker-root "$MARKER_ROOT_DIR" --launch-marker guard-launch-monitor \
    "$MARKER_TARGET" "$MARKER_SEEN" 0 >/dev/null 2>&1 || true
assert_eq "a failed token write leaves an empty .launched and no .seen" "empty:absent" \
  "$([[ -s "$MARKER_DIR/sess-8.launched" ]] && printf 'written' || printf 'empty'):$(present_or_absent "$MARKER_DIR/sess-8.seen")"
MARKER_PAYLOAD='{"session_id":"sess-8","hook_event_name":"Stop"}'
marker_launch --skip-unless-marker guard-launch-monitor 0 >/dev/null
assert_eq "and the next Stop runs the monitor" "ran" "$(target_state)"

UNWRITTEN_CASE="$PROBE_DIR/unwritten-case"
UNWRITTEN_ROOT="$UNWRITTEN_CASE/data"
mkdir -p "$UNWRITTEN_ROOT/guard-launch-monitor/s-unwritten.seen" \
  "$UNWRITTEN_ROOT/guard-launch-monitor/s-unwritten.launched" "$UNWRITTEN_CASE/tmp"
: >"$UNWRITTEN_CASE/tmp/disk-hygiene-guard-launch-monitor"
ENV_TARGET="$FIXTURE_ROOT/skills/clean/scripts/env_target.py"
printf 'import os, pathlib, sys\npathlib.Path(sys.argv[1]).write_text(os.environ.get("DISK_HYGIENE_UNWRITTEN_MARKER", "unset"))\n' \
  >"$ENV_TARGET"
unwritten_env() {
  rm -f "$UNWRITTEN_CASE/env"
  printf '{"session_id":"%s","hook_event_name":"PreToolUse"}' "$1" |
    HOME="$MARKER_HOME" TMPDIR="$UNWRITTEN_CASE/tmp" DISK_HYGIENE_UNWRITTEN_MARKER=inherited \
      bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      --marker-root "$UNWRITTEN_ROOT" --launch-marker guard-launch-monitor \
      "$ENV_TARGET" "$UNWRITTEN_CASE/env" >/dev/null 2>&1 || true
  cat "$UNWRITTEN_CASE/env" 2>/dev/null || printf 'not run'
}
assert_contains "a launch that can neither clear .seen nor open .launched names the marker" \
  "guard-launch-monitor/s-unwritten.launched" "$(unwritten_env s-unwritten)"
assert_eq "a launch that writes its token names nothing, whatever it inherited" "unset" \
  "$(unwritten_env s-written)"

if [[ -n "$REAL_PYTHON" ]]; then
  guard_row() {
    GUARD_RC=0
    printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$2" |
      HOME="$MARKER_HOME" TMPDIR="$UNWRITTEN_CASE/tmp" CLAUDE_PLUGIN_DATA="$UNWRITTEN_ROOT" \
        bash "$LAUNCHER" --marker-root "$UNWRITTEN_ROOT" --launch-marker guard-launch-monitor \
        "$GUARD" --mode engine-gate --plugin-root "$SCRIPT_DIR/.." \
        --authorized-data-root "$UNWRITTEN_ROOT" >"$UNWRITTEN_CASE/out" 2>/dev/null || GUARD_RC=$?
    GUARD_OUT="$(<"$UNWRITTEN_CASE/out")"
  }
  guard_row s-written "git status"
  assert_eq "a recorded guard launch defers with no output" "0:" "$GUARD_RC:$GUARD_OUT"
  guard_row s-unwritten "git status"
  assert_eq "an unrecorded launch's defer keeps exit 0" "0" "$GUARD_RC"
  assert_eq "and carries only a systemMessage naming the marker" "true" \
    "$(jq -e '(keys == ["systemMessage"]) and (.systemMessage | contains("s-unwritten.launched"))' \
      <<<"$GUARD_OUT" 2>/dev/null || echo false)"
  guard_row s-written "python3 /tmp/hygiene.py scan"
  written_verdict="$GUARD_RC:$(jq -c '.hookSpecificOutput' <<<"$GUARD_OUT" 2>/dev/null)"
  guard_row s-unwritten "python3 /tmp/hygiene.py scan"
  assert_eq "an unrecorded launch keeps the guard's decision and exit status" "$written_verdict" \
    "$GUARD_RC:$(jq -c '.hookSpecificOutput' <<<"$GUARD_OUT" 2>/dev/null)"
  assert_contains "and names the marker beside the decision" "s-unwritten.launched" \
    "$(jq -r '.systemMessage // ""' <<<"$GUARD_OUT" 2>/dev/null)"

  CYCLE_CASE="$PROBE_DIR/cycle-case"
  CYCLE_ROOT="$CYCLE_CASE/data"
  CYCLE_DIR="$CYCLE_ROOT/guard-launch-monitor"
  CYCLE_TRANSCRIPT="$CYCLE_CASE/transcript.jsonl"
  mkdir -p "$CYCLE_DIR" "$CYCLE_CASE/tmp"
  CYCLE_TRANSCRIPT_NATIVE="$CYCLE_TRANSCRIPT"
  if command -v cygpath >/dev/null 2>&1; then
    CYCLE_TRANSCRIPT_NATIVE="$(cygpath -m "$CYCLE_TRANSCRIPT")"
  fi
  CYCLE_STOP_PAYLOAD="{\"session_id\":\"s-cycle\",\"transcript_path\":\"$CYCLE_TRANSCRIPT_NATIVE\",\"hook_event_name\":\"Stop\"}"
  cycle_stop() {
    printf '%s' "$CYCLE_STOP_PAYLOAD" |
      HOME="$MARKER_HOME" TMPDIR="$CYCLE_CASE/tmp" \
        bash "$LAUNCHER" --marker-root "$CYCLE_ROOT" --skip-unless-marker guard-launch-monitor \
        "$MONITOR" --data-root "$CYCLE_ROOT" 2>/dev/null || true
  }
  printf '{"type":"user","message":"hello"}\n' >"$CYCLE_TRANSCRIPT"
  printf '%s-4242-17\n' "$(($(date +%s) - 120))" >"$CYCLE_DIR/s-cycle.launched"
  assert_eq "a Stop after a launch runs the monitor, which finds nothing" "" "$(cycle_stop)"
  assert_eq "and the monitor records that launch as seen" "same" \
    "$(cmp -s "$CYCLE_DIR/s-cycle.launched" "$CYCLE_DIR/s-cycle.seen" && printf 'same' || printf 'differs')"
  printf '%s\n' '{"type":"attachment","attachment":{"type":"hook_non_blocking_error","command":"node exec-bash.mjs run-python-hook.sh destructive_guard.py --mode engine-gate","exitCode":1,"durationMs":17,"stderr":"seeded"}}' \
    >>"$CYCLE_TRANSCRIPT"
  assert_eq "the next Stop skips, reading no transcript" "" "$(cycle_stop)"
  printf '%s' '{"session_id":"s-cycle","hook_event_name":"PreToolUse"}' |
    HOME="$MARKER_HOME" TMPDIR="$CYCLE_CASE/tmp" bash "$LAUNCHER" \
      --marker-root "$CYCLE_ROOT" --launch-marker guard-launch-monitor \
      "$MARKER_TARGET" "$CYCLE_CASE/ran" 0 >/dev/null 2>&1 || true
  assert_contains "a guard launch since makes the next Stop report the seeded failure" \
    "destructive_guard.py failed to run" "$(cycle_stop)"

  STOP_NODE="$(command -v node || true)"
  if ! command -v strace >/dev/null 2>&1; then
    echo "SKIP: strace not available for the Stop row census" >&2
  elif [[ -z "$STOP_NODE" ]] || [[ "$(head -c 2 "$STOP_NODE" 2>/dev/null)" == "#!" ]]; then
    echo "SKIP: node is absent or is a shim script; Stop row census not exercised" >&2
  elif ! strace -qq -e trace=execve -o /dev/null true >/dev/null 2>&1; then
    echo "SKIP: strace cannot trace on this host; Stop row census not exercised" >&2
  else
    stop_row_execs() {
      printf '%s' "$CYCLE_STOP_PAYLOAD" |
        HOME="$MARKER_HOME" TMPDIR="$CYCLE_CASE/tmp" \
          strace -f -qq -e trace=execve -o "$1" "$STOP_NODE" "$SCRIPT_DIR/exec-bash.mjs" \
          --marker-root "$CYCLE_ROOT" --skip-unless-marker guard-launch-monitor \
          "$LAUNCHER" --marker-root "$CYCLE_ROOT" --skip-unless-marker guard-launch-monitor \
          "$MONITOR" --data-root "$CYCLE_ROOT" >/dev/null 2>&1 || true
      grep -E '^[0-9]+ +execve\(' "$1" | grep -cE '\) = 0$' || true
    }
    cp "$CYCLE_DIR/s-cycle.launched" "$CYCLE_DIR/s-cycle.seen"
    assert_eq "a seen launch's Stop row execs only node (strace census)" "1" \
      "$(stop_row_execs "$PROBE_DIR/stop-seen.strace")"
    printf '%s-4243-18\n' "$(date +%s)" >"$CYCLE_DIR/s-cycle.launched"
    new_launch_execs="$(stop_row_execs "$PROBE_DIR/stop-new.strace")"
    assert_eq "a launch since .seen makes the Stop row start more than node (strace census)" "more" \
      "$([[ "$new_launch_execs" -gt 1 ]] && printf 'more' || printf '%s' "$new_launch_execs")"
  fi
else
  printf 'SKIP: %s\n' "no python3 on PATH; the guard notice and the launch-to-Stop cycle not exercised"
fi

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

PLANTED_CASE="$PROBE_DIR/planted-case"
mkdir -p "$PLANTED_CASE/link-tmp" "$PLANTED_CASE/elsewhere" "$PLANTED_CASE/own-tmp"
ln -s "$PLANTED_CASE/elsewhere" "$PLANTED_CASE/link-tmp/disk-hygiene-guard-launch-monitor"

tmp_launch() {
  rm -f "$MARKER_SEEN" "$MARKER_SEEN.argv"
  printf '%s' "$MARKER_PAYLOAD" |
    HOME="$MARKER_HOME" TMPDIR="$1" bash "$FIXTURE_ROOT/hooks/run-python-hook.sh" \
      "$2" guard-launch-monitor "$MARKER_TARGET" "$MARKER_SEEN" 0 >/dev/null 2>&1 || true
}

MARKER_PAYLOAD='{"session_id":"sess-4","hook_event_name":"Stop"}'
tmp_launch "$PLANTED_CASE/link-tmp" --skip-unless-marker
assert_eq "a symlinked tmp marker directory does not skip the monitor" "ran" "$(target_state)"
MARKER_PAYLOAD='{"session_id":"sess-4","hook_event_name":"PreToolUse"}'
tmp_launch "$PLANTED_CASE/link-tmp" --launch-marker
assert_eq "no launch marker is written through a symlinked tmp directory" "absent" \
  "$([[ -e "$PLANTED_CASE/elsewhere/sess-4.launched" ]] && printf 'present' || printf 'absent')"

if [[ "$(id -u)" == 0 ]] && id nobody >/dev/null 2>&1; then
  mkdir -p "$PLANTED_CASE/foreign-tmp/disk-hygiene-guard-launch-monitor"
  chown nobody "$PLANTED_CASE/foreign-tmp/disk-hygiene-guard-launch-monitor"
  MARKER_PAYLOAD='{"session_id":"sess-4","hook_event_name":"Stop"}'
  tmp_launch "$PLANTED_CASE/foreign-tmp" --skip-unless-marker
  assert_eq "a tmp marker directory another user owns does not skip the monitor" \
    "ran" "$(target_state)"
else
  printf 'SKIP: %s\n' "a tmp launch-marker directory another user owns (needs root to create one)"
fi

MARKER_PAYLOAD='{"session_id":"sess-5","hook_event_name":"PreToolUse"}'
tmp_launch "$PLANTED_CASE/own-tmp" --launch-marker
assert_eq "a launch records the session in its own tmp directory" "present" \
  "$([[ -f "$PLANTED_CASE/own-tmp/disk-hygiene-guard-launch-monitor/sess-5.launched" ]] &&
    printf 'present' || printf 'absent')"
case "${OSTYPE:-}" in
  msys* | cygwin* | win32) ;;
  *)
    own_mode="$(ls -ld "$PLANTED_CASE/own-tmp/disk-hygiene-guard-launch-monitor")"
    assert_eq "the launch creates its tmp marker directory with mode 700" "drwx------" \
      "${own_mode:0:10}"
    ;;
esac
MARKER_PAYLOAD='{"session_id":"sess-5","hook_event_name":"Stop"}'
tmp_launch "$PLANTED_CASE/own-tmp" --skip-unless-marker
assert_eq "a recorded session in an own tmp directory runs the monitor" "ran" "$(target_state)"
MARKER_PAYLOAD='{"session_id":"sess-6","hook_event_name":"Stop"}'
tmp_launch "$PLANTED_CASE/own-tmp" --skip-unless-marker
assert_eq "an unrecorded session in an own tmp directory skips the monitor" \
  "skipped" "$(target_state)"

guard_rows="$(jq '[.hooks.PreToolUse[].hooks[] |
  select(([.command] + ((.args // []) | map(tostring)) | join(" ")) | contains("destructive_guard.py"))] | length' \
  "$HOOKS_JSON")"
guard_marked="$(jq '[.hooks.PreToolUse[].hooks[] |
  select(([.command] + ((.args // []) | map(tostring)) | join(" ")) | contains("destructive_guard.py")) |
  select(([.command] + ((.args // []) | map(tostring)) | join(" ")) | contains("--launch-marker guard-launch-monitor"))] | length' \
  "$HOOKS_JSON")"
assert_eq "every engine-gate row records the session it launched in" \
  "$guard_rows" "$guard_marked"
assert_eq "the Stop row skips a session that launched no guard" "1" \
  "$(jq '[.hooks.Stop[].hooks[] |
    select(([.command] + ((.args // []) | map(tostring)) | join(" ")) | contains("--skip-unless-marker guard-launch-monitor"))] | length' \
    "$HOOKS_JSON")"
assert_eq "the launcher skips the Stop row before bash with the script's own marker flags" "true" \
  "$(jq '[.hooks.Stop[].hooks[].args | select(map(tostring) | join(" ") | contains("guard_launch_monitor.py")) |
    .[1:6] == ["--marker-root", "${CLAUDE_PLUGIN_DATA}", "--skip-unless-marker", "guard-launch-monitor",
      "${CLAUDE_PLUGIN_ROOT}/hooks/run-python-hook.sh"] and .[6:10] == .[1:5]] == [true]' "$HOOKS_JSON" | tr -d '\r')"

assert_eq "one SessionStart entry with one handler" "[1]" \
  "$(jq -c '[.hooks.SessionStart[] | .hooks | length]' "$HOOKS_JSON")"
assert_eq "the SessionStart handler is the node-or-skip resume notice" "true" \
  "$(jq '.hooks.SessionStart[0].hooks[0] | (has("args") | not) and (.command | startswith("sh \"${CLAUDE_PLUGIN_ROOT}/lib/node-or-skip.sh\" \"${CLAUDE_PLUGIN_ROOT}/hooks/resume-notice.mjs\" \"--marker-root\" \"${CLAUDE_PLUGIN_DATA}\"; "))' "$HOOKS_JSON" | tr -d '\r')"
assert_eq "the clean expansion records the session the resume notice reads" "true" \
  "$(jq '[.hooks.UserPromptExpansion[].hooks[].args | .[1:6] == ["${CLAUDE_PLUGIN_ROOT}/hooks/run-python-hook.sh", "--marker-root", "${CLAUDE_PLUGIN_DATA}", "--launch-marker", "clean-invoked"]] == [true]' "$HOOKS_JSON" | tr -d '\r')"
assert_eq "a model load of clean records the same marker, with no target to launch" "true" \
  "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Skill") | .hooks[] | has("if") == false and .args[3:] == ["${CLAUDE_PLUGIN_ROOT}/hooks/run-python-hook.sh", "--marker-root", "${CLAUDE_PLUGIN_DATA}", "--launch-marker", "clean-invoked", "--only-skill", "disk-hygiene:clean"]] == [true]' "$HOOKS_JSON" | tr -d '\r')"

pass "all run-python-hook contract checks"
