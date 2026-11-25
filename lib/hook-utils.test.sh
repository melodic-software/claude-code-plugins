#!/usr/bin/env bash

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# --- Source the lib under test -----------------------------------------------
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

WORK="$(mktemp -d)"
export TMPDIR="$WORK"
cleanup_work() { rm -rf "$WORK"; }
trap cleanup_work EXIT

# shellcheck source=hook-test-sink.sh
source "$HOOK_DIR/hook-test-sink.sh"

SINK_POLLS=750

make_logging_shim() {
  local dir="$1" tool="$2" real
  real=$(type -P "$2") || real=""
  [[ -n "$real" ]] || return 1
  cat >"$dir/$tool" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$tool" >>"$dir/log"
exec "$real" "\$@"
EOF
  chmod +x "$dir/$tool"
}

unset HOOK_TELEMETRY_SINK 2>/dev/null || true
out=$(hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"foo.py","findings":[]}' 2>/dev/null)
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "sink unset: returns 0"
else
  fail "sink unset: expected 0, got $rc"
fi
if [[ -z "$out" ]]; then
  ok "sink unset: no output"
else
  fail "sink unset: unexpected output: $out"
fi

EMPTY_BIN="$(mktemp -d)"
SINK_FILE2="$(mktemp)"
STUB2="$(mktemp)"
cat >"$STUB2" <<EOF
#!/bin/bash
while IFS= read -r line || [[ -n "\$line" ]]; do printf '%s\n' "\$line"; done >"$SINK_FILE2"
EOF
chmod +x "$STUB2"
# shellcheck disable=SC2030,SC2031
out_nojq=$(
  export HOOK_TELEMETRY_SINK="$STUB2"
  PATH="$EMPTY_BIN" hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"foo.py","findings":[]}' 2>/dev/null
  echo $? >"$WORK/nojq.rc"
  wait
)
rc_nojq=$(<"$WORK/nojq.rc")
wait_for_sink "$SINK_FILE2" "$SINK_POLLS" || true
rmdir "$EMPTY_BIN" 2>/dev/null || true
if [[ $rc_nojq -eq 0 ]]; then
  ok "jq absent: returns 0"
else
  fail "jq absent: expected 0, got $rc_nojq"
fi
if [[ -z "$out_nojq" ]]; then
  ok "jq absent: nothing on stdout"
else
  fail "jq absent: unexpected output: $out_nojq"
fi
if [[ -s "$SINK_FILE2" ]] && grep -q '"hook":"sample-hook","hook_event":"PostToolUse","status":"ok"' "$SINK_FILE2"; then
  ok "jq absent (empty PATH): envelope still delivered by the builtin path"
else
  fail "jq absent (empty PATH): envelope not delivered: $(cat "$SINK_FILE2" 2>/dev/null)"
fi
: >"$SINK_FILE2"
# shellcheck disable=SC2030,SC2031,SC2329  # subshell-local by design; jq is invoked through the lib
(
  jq() {
    echo "jq was invoked on the builtin path" >&2
    return 127
  }
  export HOOK_TELEMETRY_SINK="$STUB2"
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"foo.py","findings":[]}'
  wait
) 2>"$SINK_FILE2.err"
wait_for_sink "$SINK_FILE2" "$SINK_POLLS" || true
if [[ -s "$SINK_FILE2" ]] && ! grep -q 'jq was invoked' "$SINK_FILE2.err"; then
  ok "jq shadowed: envelope delivered without invoking jq"
else
  fail "jq shadowed: delivered=$([[ -s "$SINK_FILE2" ]] && echo yes || echo no) stderr=$(cat "$SINK_FILE2.err")"
fi
rm -f "$SINK_FILE2" "$SINK_FILE2.err" "$STUB2"

SINK_FILE="$(mktemp)"
cleanup_t3() {
  rm -f "$SINK_FILE"
  cleanup_work
}
trap cleanup_t3 EXIT

# Use a file-writing sink to capture the envelope.
# shellcheck disable=SC2031  # prior subshell export is intentionally scoped there
HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$SINK_FILE\"")"
export HOOK_TELEMETRY_SINK
data_json='{"tool":"Write","file":"src/foo.py","findings":["src/foo.py:1:8: F401 os imported but unused"]}'
start=$EPOCHREALTIME
hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$start" "$data_json" 2>/dev/null
wait_for_sink "$SINK_FILE" "$SINK_POLLS"
unset HOOK_TELEMETRY_SINK

if [[ -s "$SINK_FILE" ]]; then
  ok "envelope shape: sink received data"
  if check_envelope "$SINK_FILE"; then ok "envelope shape: matches envelope schema"; else fail "envelope shape: does not match envelope schema. envelope=$(cat "$SINK_FILE")"; fi
  for subfield in tool file findings; do
    if jq -e ".data | has(\"$subfield\")" "$SINK_FILE" >/dev/null 2>&1; then
      ok "envelope shape: data.$subfield present"
    else
      fail "envelope shape: data.$subfield missing. data=$(jq .data "$SINK_FILE")"
    fi
  done
  sv=$(jq -r '.schema_version' "$SINK_FILE")
  if [[ "$sv" == "1.1" ]]; then
    ok "envelope: schema_version is 1.1"
  else
    fail "envelope: schema_version expected 1.1, got $sv"
  fi
  hook_val=$(jq -r '.hook' "$SINK_FILE")
  if [[ "$hook_val" == "sample-hook" ]]; then
    ok "envelope: hook is sample-hook"
  else
    fail "envelope: hook expected sample-hook, got $hook_val"
  fi
  he=$(jq -r '.hook_event' "$SINK_FILE")
  if [[ "$he" == "PostToolUse" ]]; then
    ok "envelope: hook_event is PostToolUse"
  else
    fail "envelope: hook_event expected PostToolUse, got $he"
  fi
  status_val=$(jq -r '.status' "$SINK_FILE")
  if [[ "$status_val" == "ok" ]]; then
    ok "envelope: status is ok"
  else
    fail "envelope: status expected ok, got $status_val"
  fi
else
  fail "envelope shape: sink file empty — emit did not fire or sink did not write"
  fail "envelope shape: envelope not verifiable (no envelope)"
  for subfield in tool file findings; do
    fail "envelope shape: data.$subfield not verifiable (no envelope)"
  done
  for value in schema_version hook hook_event status; do
    fail "envelope: $value value not verifiable (no envelope)"
  done
fi

# --- Test 4: timestamp is UTC RFC3339 with Z suffix --------------------------
if [[ -s "$SINK_FILE" ]]; then
  ts=$(jq -r '.timestamp' "$SINK_FILE")
  if [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    ok "timestamp: matches RFC3339 UTC pattern"
  else
    fail "timestamp: does not match pattern: $ts"
  fi
  utc_h=$(TZ=UTC date +%H)
  ts_h="${ts:11:2}"
  h_diff=$(((${ts_h#0} - ${utc_h#0} + 24) % 24))
  if [[ $h_diff -le 1 || $h_diff -ge 23 ]]; then
    ok "timestamp: UTC hour aligns with system UTC"
  else
    fail "timestamp: hour drift vs UTC: ts_h=$ts_h utc_h=$utc_h diff=$h_diff"
  fi
else
  fail "timestamp: no envelope to check"
  fail "timestamp: UTC alignment not verifiable"
fi

if [[ -s "$SINK_FILE" ]]; then
  dur=$(jq '.duration_ms' "$SINK_FILE")
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$SINK_FILE" >/dev/null 2>&1; then
    ok "duration_ms: is non-negative integer (value=$dur)"
  else
    fail "duration_ms: not a non-negative integer: $dur"
  fi
else
  fail "duration_ms: no envelope to check"
fi

rm -f "$SINK_FILE"
trap cleanup_work EXIT

SINK_FILE2="$(mktemp)"
HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$SINK_FILE2\"")"
export HOOK_TELEMETRY_SINK
hook::emit_telemetry "sample-hook" "PostToolUse" "skipped" "$EPOCHREALTIME" '{"tool":"","file":"","findings":[]}' 2>/dev/null
wait_for_sink "$SINK_FILE2" "$SINK_POLLS"
unset HOOK_TELEMETRY_SINK

if [[ -s "$SINK_FILE2" ]]; then
  st2=$(jq -r '.status' "$SINK_FILE2")
  if [[ "$st2" == "skipped" ]]; then
    ok "status skipped: correctly emitted"
  else
    fail "status skipped: got $st2"
  fi
else
  fail "status skipped: no envelope written"
fi
rm -f "$SINK_FILE2"

ROOT7="$(mktemp -d)"
mkdir -p "$ROOT7/.claude/hooks"
REL7=".claude/hooks/sink.sh"
OUT7="$(mktemp)"
cat >"$ROOT7/$REL7" <<EOF
#!/usr/bin/env bash
cat >"$OUT7"
EOF
chmod +x "$ROOT7/$REL7"
export HOOK_TELEMETRY_SINK="$REL7"
hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.py","findings":[]}' "$ROOT7" 2>/dev/null
wait_for_sink "$OUT7" "$SINK_POLLS"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT7" ]] && [[ "$(jq -r '.hook' "$OUT7")" == "sample-hook" ]]; then
  ok "relative sink: resolved against repo_root arg, envelope delivered"
else
  fail "relative sink: not resolved against repo_root arg (out empty or wrong)"
fi
rm -rf "$ROOT7" "$OUT7"

ROOT8="$(mktemp -d)"
mkdir -p "$ROOT8/.claude/hooks"
OUT8="$(mktemp)"
cat >"$ROOT8/.claude/hooks/sink.sh" <<EOF
#!/usr/bin/env bash
cat >"$OUT8"
EOF
chmod +x "$ROOT8/.claude/hooks/sink.sh"
export HOOK_TELEMETRY_SINK=".claude/hooks/sink.sh"
CLAUDE_PROJECT_DIR="$ROOT8" hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.py","findings":[]}' 2>/dev/null
wait_for_sink "$OUT8" "$SINK_POLLS"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT8" ]]; then
  ok "relative sink: resolved against CLAUDE_PROJECT_DIR fallback"
else
  fail "relative sink: CLAUDE_PROJECT_DIR fallback did not resolve"
fi
rm -rf "$ROOT8" "$OUT8"

OUT9="$(mktemp)"
rm -f "$OUT9" # ensure absent
export HOOK_TELEMETRY_SINK="relative/no/anchor/sink.sh"
(
  unset CLAUDE_PROJECT_DIR 2>/dev/null || true
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.py","findings":[]}' 2>/dev/null
)
rc9=$?
sleep 0.2
unset HOOK_TELEMETRY_SINK
if [[ $rc9 -eq 0 ]] && [[ ! -s "$OUT9" ]]; then
  ok "relative sink, no anchor: fail-open skip (rc 0, no write)"
else
  fail "relative sink, no anchor: expected skip (rc=$rc9, out exists=$([[ -s "$OUT9" ]] && echo y || echo n))"
fi
rm -f "$OUT9"

OUT10="$(mktemp)"
ABS10="$(make_sink "cat >\"$OUT10\"")" # mktemp path is absolute
export HOOK_TELEMETRY_SINK="$ABS10"
hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.py","findings":[]}' "/some/ignored/root" 2>/dev/null
wait_for_sink "$OUT10" "$SINK_POLLS"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT10" ]] && [[ "$(jq -r '.hook' "$OUT10")" == "sample-hook" ]]; then
  ok "absolute sink: passes through unchanged (repo_root ignored)"
else
  fail "absolute sink: did not pass through"
fi
rm -f "$ABS10" "$OUT10"

put_launcher() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\ncat >%q\n' "$2" >"$1/hook-telemetry-sink.sh"
  chmod +x "$1/hook-telemetry-sink.sh"
}
emit_reserved() {
  local out="$1"
  shift
  (
    unset CLAUDE_PLUGIN_DATA CLAUDE_CONFIG_DIR
    for kv in "$@"; do export "${kv?}"; done
    HOOK_TELEMETRY_SINK="${RESERVED:-@session-telemetry}" hook::emit_telemetry "sample-hook" "PostToolUse" "ok" \
      "$EPOCHREALTIME" '{"tool":"Write","file":"x.py"}' "$WORK/repo10b" 2>/dev/null
  )
  wait_for_sink "$out" "${EMIT_POLLS:-$SINK_POLLS}"
}
mkdir -p "$WORK/repo10b"

CFG10b="$WORK/cfg10b"
OUT10b1="$WORK/out10b1"
put_launcher "$CFG10b/plugins/data/session-telemetry-mkt" "$OUT10b1"
if emit_reserved "$OUT10b1" "CLAUDE_CONFIG_DIR=$CFG10b"; then
  ok "@session-telemetry: a repository hook finds the launcher under CLAUDE_CONFIG_DIR"
else
  fail "@session-telemetry: no envelope through the CLAUDE_CONFIG_DIR launcher"
fi

HOME10b="$WORK/home10b"
OUT10b2="$WORK/out10b2"
put_launcher "$HOME10b/.claude/plugins/data/session-telemetry-mkt" "$OUT10b2"
if emit_reserved "$OUT10b2" "HOME=$HOME10b"; then
  ok "@session-telemetry: with no CLAUDE_CONFIG_DIR the launcher is found under \$HOME/.claude"
else
  fail "@session-telemetry: no envelope through the \$HOME/.claude launcher"
fi

DATA10b="$WORK/data10b/plugins/data"
OUT10b3="$WORK/out10b3"
mkdir -p "$DATA10b/session-telemetry-a" "$DATA10b/guardrails-mkt"
put_launcher "$DATA10b/session-telemetry-b" "$OUT10b3"
if emit_reserved "$OUT10b3" "CLAUDE_PLUGIN_DATA=$DATA10b/guardrails-mkt/" "CLAUDE_CONFIG_DIR=$WORK/elsewhere"; then
  ok "@session-telemetry: a plugin hook finds the launcher beside its own data dir, past a sibling with none"
else
  fail "@session-telemetry: no envelope through the sibling launcher"
fi

OUT10b4="$WORK/out10b4"
OUT10b4_stale="$WORK/out10b4-stale"
put_launcher "$DATA10b/session-telemetry-a" "$OUT10b4"
put_launcher "$DATA10b/session-telemetry-z" "$OUT10b4_stale"
touch -t 203001010000 "$DATA10b/session-telemetry-a/hook-telemetry-sink.sh"
touch -t 202001010000 "$DATA10b/session-telemetry-z/hook-telemetry-sink.sh"
if emit_reserved "$OUT10b4" "CLAUDE_PLUGIN_DATA=$DATA10b/session-telemetry-z"; then
  ok "@session-telemetry: the newest launcher wins, even over the caller's own"
else
  fail "@session-telemetry: the newest launcher was not chosen"
fi
if [[ -e "$OUT10b4_stale" ]]; then
  fail "@session-telemetry: the older launcher ran"
else
  ok "@session-telemetry: the older launcher was not run"
fi

DATAW10b="$WORK/dataw10b/plugins/data"
OUT10b7="$WORK/out10b7"
mkdir -p "$DATAW10b/guardrails-mkt"
put_launcher "$DATAW10b/session-telemetry-mkt" "$OUT10b7"
if emit_reserved "$OUT10b7" "CLAUDE_PLUGIN_DATA=${DATAW10b}\\guardrails-mkt\\" "CLAUDE_CONFIG_DIR=$WORK/elsewhere"; then
  ok "@session-telemetry: a backslash CLAUDE_PLUGIN_DATA (Windows native) still finds the sibling launcher"
else
  fail "@session-telemetry: a backslash CLAUDE_PLUGIN_DATA found no launcher"
fi

CFGF10b="$WORK/cfgf10b"
OUT10b8="$WORK/out10b8"
mkdir -p "$WORK/lonely10b/plugins/data/guardrails-mkt"
put_launcher "$CFGF10b/plugins/data/session-telemetry-mkt" "$OUT10b8"
if emit_reserved "$OUT10b8" "CLAUDE_PLUGIN_DATA=$WORK/lonely10b/plugins/data/guardrails-mkt" "CLAUDE_CONFIG_DIR=$CFGF10b"; then
  ok "@session-telemetry: with no sibling launcher a plugin hook falls through to the config dir"
else
  fail "@session-telemetry: no fall-through to the config dir"
fi

OUT10b5="$WORK/out10b5"
printf '#!/usr/bin/env bash\ncat >%q\n' "$OUT10b5" >"$WORK/repo10b/@session-telemetry"
chmod +x "$WORK/repo10b/@session-telemetry"
if EMIT_POLLS=25 emit_reserved "$OUT10b5" "CLAUDE_CONFIG_DIR=$WORK/empty-cfg"; then
  fail "@session-telemetry: with no launcher the value was joined onto the repo root and run"
else
  ok "@session-telemetry: with no launcher nothing is sent (fail-open)"
fi

CFGH10b="$WORK/cfgh10b"
OUT10b9="$WORK/out10b9"
OUT10b9_old="$WORK/out10b9-old"
put_launcher "$CFGH10b/plugins/data/session-telemetry-mkt" "$OUT10b9"
put_launcher "$CFGH10b/plugins/data/harness-ops-mkt" "$OUT10b9_old"
touch -t 203001010000 "$CFGH10b/plugins/data/harness-ops-mkt/hook-telemetry-sink.sh"
if RESERVED=@harness-ops emit_reserved "$OUT10b9" "CLAUDE_CONFIG_DIR=$CFGH10b"; then
  ok "@harness-ops: resolves to the session-telemetry launcher"
else
  fail "@harness-ops: no envelope through the session-telemetry launcher"
fi
if [[ -e "$OUT10b9_old" ]]; then
  fail "@harness-ops: a harness-ops data-dir launcher ran"
else
  ok "@harness-ops: a harness-ops data-dir launcher is not run, even when newer"
fi
OUT10b10="$WORK/out10b10"
put_launcher "$WORK/cfgh10b-old/plugins/data/harness-ops-mkt" "$OUT10b10"
if RESERVED=@session-telemetry EMIT_POLLS=25 emit_reserved "$OUT10b10" "CLAUDE_CONFIG_DIR=$WORK/cfgh10b-old"; then
  fail "@session-telemetry: a harness-ops launcher alone was run"
else
  ok "@session-telemetry: with only a harness-ops launcher nothing is sent (fail-open)"
fi

OUT10b6="$WORK/out10b6"
printf '#!/usr/bin/env bash\ncat >%q\n' "$OUT10b6" >"$WORK/repo10b/@other"
chmod +x "$WORK/repo10b/@other"
(HOOK_TELEMETRY_SINK=@other hook::emit_telemetry "sample-hook" "PostToolUse" "ok" \
  "$EPOCHREALTIME" '{}' "$WORK/repo10b" 2>/dev/null)
if wait_for_sink "$OUT10b6" 25; then
  fail "an unknown @ value was joined onto the repo root and run"
else
  ok "an unknown @ value is reserved: nothing is sent"
fi

# shellcheck disable=SC2030 # the subshell-local override is the point; Test 12b's later read of the host's real OSTYPE is what pairs this with SC2031
norm_as() { (
  OSTYPE="$1"
  local __norm=""
  hook::normalize_path_to __norm "$2"
  printf '%s' "$__norm"
); }
assert_norm() { # <ostype> <input> <expected> <desc>
  local got
  got="$(norm_as "$1" "$2")"
  if [[ "$got" == "$3" ]]; then
    ok "normalize_path[$1]: $4"
  else
    fail "normalize_path[$1]: $4 — expected '$3', got '$got'"
  fi
}

assert_norm msys "/c/Repo" "C:/repo" "msys folds /c/Repo → C:/repo"
assert_norm msys "C:/Repo" "C:/repo" "msys folds C:/Repo → C:/repo"
assert_norm msys "/c/Repo/Sub" "C:/repo/sub" "msys folds nested path"
assert_norm msys 'C:\Repo\x' "C:/repo/x" "msys: backslashes → slashes then fold"
assert_norm cygwin "/c/Repo" "C:/repo" "cygwin folds like msys"

assert_norm linux-gnu "/c/Repo" "/c/Repo" "linux leaves /c/Repo unchanged"
assert_norm linux-gnu "/c/repo" "/c/repo" "linux leaves /c/repo unchanged"
assert_norm linux-gnu "/opt/App/Sub" "/opt/App/Sub" "linux leaves normal path unchanged"
assert_norm linux-gnu 'a\b' "a/b" "linux still converts backslashes" # portability-ok: literal backslash in a path fixture, not a GNU grep \b word boundary

if [[ "$(norm_as linux-gnu /c/Repo)" != "$(norm_as linux-gnu /c/repo)" ]]; then
  ok "normalize_path[linux-gnu]: /c/Repo and /c/repo stay distinct"
else
  fail "normalize_path[linux-gnu]: /c/Repo and /c/repo collapsed (membership-guard regression)"
fi

rfp() { # <project_dir> <file_path> → stdout: emitted path; rc: guard verdict
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -n --arg fp "$2" '{tool_input: {file_path: $fp}}' |
    (
      # shellcheck disable=SC2030 # subshell-local by design: the override must not leak into the suite
      export CLAUDE_PROJECT_DIR="$1"
      hook::read_file_path
    )
}
try_symlink() { # <target> <link> → rc 0 iff a REAL symlink now exists
  MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null
  [[ -L "$2" ]]
}

PROJ12="$(mktemp -d)"
OUTSIDE12="$(mktemp -d)"
SIB12="${PROJ12}-sibling"
mkdir -p "$SIB12"
echo 'x = 1' >"$PROJ12/inside.py"
echo 'y = 2' >"$OUTSIDE12/outside.py"
echo 'z = 3' >"$SIB12/near.py"

if got=$(rfp "$PROJ12" "$PROJ12/inside.py") && [[ "$got" == "$PROJ12/inside.py" ]]; then
  ok "read_file_path: in-project file accepted, original path emitted"
else
  fail "read_file_path: in-project file rejected or path mangled (got '$got')"
fi

if got=$(rfp "$PROJ12" "$SIB12/near.py"); then
  fail "read_file_path: prefix-sibling admitted (got '$got')"
else
  ok "read_file_path: prefix-sibling rejected"
fi

if try_symlink "$OUTSIDE12/outside.py" "$PROJ12/escape.py"; then
  if got=$(rfp "$PROJ12" "$PROJ12/escape.py"); then
    fail "read_file_path: escaping symlink admitted (got '$got')"
  else
    ok "read_file_path: escaping symlink rejected"
  fi
else
  ok "read_file_path: escaping symlink SKIPPED (host cannot create symlinks)"
fi

if try_symlink "$PROJ12/inside.py" "$PROJ12/alias.py"; then
  if got=$(rfp "$PROJ12" "$PROJ12/alias.py") && [[ "$got" == "$PROJ12/alias.py" ]]; then
    ok "read_file_path: in-project symlink accepted, original path emitted"
  else
    fail "read_file_path: in-project symlink rejected or path mangled (got '$got')"
  fi
else
  ok "read_file_path: in-project symlink SKIPPED (host cannot create symlinks)"
fi

if try_symlink "$OUTSIDE12" "$PROJ12/subdir"; then
  if got=$(rfp "$PROJ12" "$PROJ12/subdir/outside.py"); then
    fail "read_file_path: symlinked-directory escape admitted (got '$got')"
  else
    ok "read_file_path: symlinked-directory escape rejected"
  fi
else
  ok "read_file_path: symlinked-directory escape SKIPPED (host cannot create symlinks)"
fi

if try_symlink "$PROJ12" "$OUTSIDE12/projlink"; then
  if got=$(rfp "$OUTSIDE12/projlink" "$PROJ12/inside.py") && [[ "$got" == "$PROJ12/inside.py" ]]; then
    ok "read_file_path: symlinked project root resolves to real root"
  else
    fail "read_file_path: symlinked project root rejected real-root file (got '$got')"
  fi
else
  ok "read_file_path: symlinked project root SKIPPED (host cannot create symlinks)"
fi

rm -rf "$PROJ12" "$OUTSIDE12" "$SIB12"

# shellcheck disable=SC2031 # Test 11's norm_as sets OSTYPE only inside its own subshell; this reads the host's real value
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == win32 ]] &&
  command -v cygpath >/dev/null 2>&1; then
  PROJ12B="$(mktemp -d)"
  OUT12B="$(mktemp -d)"
  echo 'x = 1' >"$PROJ12B/shortname-target.py"
  echo 'y = 2' >"$OUT12B/shortname-outside.py"
  echo 'z = 3' >"$PROJ12B/note~s.py"
  PROJ12B_M=$(cygpath -m -- "$PROJ12B")
  short_in=$(cygpath -s -m -- "$PROJ12B/shortname-target.py" 2>/dev/null)
  plain_in=$(cygpath -m -- "$PROJ12B/shortname-target.py")

  if got=$(rfp "$PROJ12B_M" "$PROJ12B_M/note~s.py") && [[ "$got" == "$PROJ12B_M/note~s.py" ]]; then
    ok "read_file_path: literal-tilde long name accepted, original path emitted"
  else
    fail "read_file_path: literal-tilde long name rejected or mangled (got '$got')"
  fi

  if [[ -n "$short_in" && "$short_in" != "$plain_in" ]]; then
    if got=$(rfp "$PROJ12B_M" "$short_in") && [[ "$got" == "$short_in" ]]; then
      ok "read_file_path: short-form in-project file accepted"
    else
      fail "read_file_path: short-form in-project file rejected (got '$got') — 8.3-blind membership guard"
    fi
    short_proj=$(cygpath -s -m -- "$PROJ12B" 2>/dev/null)
    if got=$(rfp "$short_proj" "$PROJ12B_M/shortname-target.py") && [[ "$got" == "$PROJ12B_M/shortname-target.py" ]]; then
      ok "read_file_path: short-form project dir admits in-project file"
    else
      fail "read_file_path: short-form project dir rejected in-project file (got '$got')"
    fi
    short_out=$(cygpath -s -m -- "$OUT12B/shortname-outside.py" 2>/dev/null)
    if got=$(rfp "$PROJ12B_M" "$short_out"); then
      fail "read_file_path: short-form OUT-of-project file admitted (got '$got')"
    else
      ok "read_file_path: short-form out-of-project file still rejected"
    fi
  else
    ok "read_file_path: 8.3 short-form SKIPPED (this volume does not generate short names — no coverage here, not a pass; the defect is volume-scoped)"
  fi
  rm -rf "$PROJ12B" "$OUT12B"
else
  ok "read_file_path: 8.3 short-form SKIPPED (non-Windows host or no cygpath — 8.3 names are a Windows volume feature)"
fi

rfp_tmp() { # <temp_root> <project_dir> <file_path> → stdout: path; rc: verdict
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -n --arg fp "$3" '{tool_input: {file_path: $fp}}' |
    (
      # shellcheck disable=SC2030,SC2031 # subshell-local by design: the overrides must not leak into the suite
      export CLAUDE_PROJECT_DIR="$2" TMPDIR="$1" TMP="$1" TEMP="$1"
      hook::read_file_path
    )
}

PROJ12C=""
if [[ -n "${HOME:-}" && -d "${HOME:-}" ]]; then
  PROJ12C=$(mktemp -d "$HOME/.hook-utils-test.XXXXXX" 2>/dev/null) || PROJ12C=""
fi
PROJ12C_NORM=""
if [[ -n "$PROJ12C" ]]; then
  PROJ12C_PHYS=""
  hook::physical_path_to PROJ12C_PHYS "$PROJ12C" || :
  hook::normalize_path_to PROJ12C_NORM "$PROJ12C_PHYS"
fi
if [[ -n "$PROJ12C" ]] && ! hook::under_temp_root "$PROJ12C_NORM"; then
  mkdir -p "$PROJ12C/scratchpad"
  echo 'y = 2' >"$PROJ12C/scratchpad/inventory.py"
  echo 'x = 1' >"$PROJ12C/inside.py"

  if got=$(rfp_tmp "$PROJ12C/scratchpad" "$PROJ12C" "$PROJ12C/scratchpad/inventory.py"); then
    fail "read_file_path: temp-tree file admitted under a non-temp project root (got '$got') — home-shaped project dir admits the harness scratchpad"
  else
    ok "read_file_path: temp-tree file rejected under a non-temp project root"
  fi

  if got=$(rfp_tmp "$PROJ12C/scratchpad" "$PROJ12C/scratchpad" "$PROJ12C/scratchpad/inventory.py") &&
    [[ "$got" == "$PROJ12C/scratchpad/inventory.py" ]]; then
    ok "read_file_path: temp-rooted project still admits its own files"
  else
    fail "read_file_path: temp-rooted project rejected its own file (got '$got') — the mktemp-fixture exemption regressed"
  fi

  if got=$(rfp_tmp "$PROJ12C/scratchpad" "$PROJ12C" "$PROJ12C/inside.py") &&
    [[ "$got" == "$PROJ12C/inside.py" ]]; then
    ok "read_file_path: in-project file outside the temp tree still accepted"
  else
    fail "read_file_path: in-project file outside the temp tree rejected (got '$got')"
  fi

  if command -v cygpath >/dev/null 2>&1 &&
    win_tmp=$(cygpath -w -- "$PROJ12C/scratchpad" 2>/dev/null) && [[ -n "$win_tmp" ]]; then
    got=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -n --arg fp "$PROJ12C/scratchpad/inventory.py" '{tool_input: {file_path: $fp}}' |
      (
        # shellcheck disable=SC2030,SC2031 # subshell-local by design
        export CLAUDE_PROJECT_DIR="$PROJ12C" TMP="$win_tmp" TEMP="$win_tmp"
        unset TMPDIR
        hook::read_file_path
      ))
    if [[ -n "$got" ]]; then
      fail "read_file_path: backslash-spelled temp root not recognized (got '$got')"
    else
      ok "read_file_path: temp root spelled in Windows backslash form is recognized"
    fi
  else
    ok "read_file_path: backslash temp-root spelling SKIPPED (no cygpath — the spelling is Windows-only)"
  fi

  rm -rf "$PROJ12C"
else
  [[ -n "$PROJ12C" ]] && rm -rf "$PROJ12C"
  ok "read_file_path: temp-tree scoping SKIPPED (no writable HOME outside the temp tree on this host — no coverage here, not a pass)"
fi

if command -v git >/dev/null 2>&1; then
  PROJ12E=$(mktemp -d)
  SCRATCH12E=$(mktemp -d)
  (
    cd "$PROJ12E" || exit 1
    git init -q .
    echo in-repo >tracked.md
    git add tracked.md
    git -c user.email=t@e.st -c user.name=t commit -q -m init
  ) >/dev/null 2>&1
  echo scratch >"$SCRATCH12E/outside.md"
  got_in=$(
    unset CLAUDE_PROJECT_DIR
    printf '%s' "{\"tool_input\":{\"file_path\":\"$PROJ12E/tracked.md\"}}" |
      hook::read_file_path
  ) || got_in=""
  got_out=$(
    unset CLAUDE_PROJECT_DIR
    printf '%s' "{\"tool_input\":{\"file_path\":\"$SCRATCH12E/outside.md\"}}" |
      hook::read_file_path
  ) || got_out=""
  if [[ "$got_in" == "$PROJ12E/tracked.md" ]]; then
    ok "read_file_path: in-repo file accepted with CLAUDE_PROJECT_DIR unset"
  else
    fail "read_file_path: in-repo file rejected with CLAUDE_PROJECT_DIR unset (got '$got_in')"
  fi
  if [[ -z "$got_out" ]]; then
    ok "read_file_path: out-of-tree file rejected with CLAUDE_PROJECT_DIR unset"
  else
    fail "read_file_path: out-of-tree file admitted with CLAUDE_PROJECT_DIR unset (got '$got_out')"
  fi
  rm -rf "$PROJ12E" "$SCRATCH12E"
else
  ok "read_file_path: git worktree scope SKIPPED (git not on PATH)"
fi

NO_GIT_BIN12F="$(mktemp -d)"
for _cmd12f in jq realpath readlink; do
  _src12f=$(command -v "$_cmd12f" 2>/dev/null) || continue
  ln -s "$_src12f" "$NO_GIT_BIN12F/$_cmd12f"
done
unset _cmd12f _src12f
IN_TREE12F="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/README.md"
rc_no_git=0
got_no_git=$(
  unset CLAUDE_PROJECT_DIR
  PATH="$NO_GIT_BIN12F" \
    printf '%s' "{\"tool_input\":{\"file_path\":\"$IN_TREE12F\"}}" |
    PATH="$NO_GIT_BIN12F" hook::read_file_path
) && rc_no_git=0 || rc_no_git=$?
rm -rf "$NO_GIT_BIN12F"
if [[ "$rc_no_git" -eq 1 && -z "$got_no_git" ]]; then
  ok "read_file_path: git absent with CLAUDE_PROJECT_DIR unset rejects file"
else
  fail "read_file_path: git absent admitted file or wrong status (rc=$rc_no_git got='$got_no_git')"
fi

if (
  # shellcheck disable=SC2030,SC2031 # subshell-local by design: the overrides must not leak into the suite
  export TMPDIR=/ TMP=/ TEMP=/
  hook::under_temp_root "$HOME/anywhere/at-all.py"
); then
  ok "under_temp_root: root temp candidate contains every path"
else
  fail "under_temp_root: root temp candidate discarded — '/' trimmed to empty"
fi

utr_stub() (
  # shellcheck disable=SC2030,SC2031 # subshell-local by design: the overrides must not leak into the suite
  OSTYPE="$1"
  _utr_cand="$2"
  hook::_temp_root_candidates() { _HOOK_TEMP_CANDS=("$_utr_cand"); }
  hook::_physical_cached_to() { printf -v "$1" '%s' "$2"; }
  hook::under_temp_root "$3"
)
UTR_CAND="C:/Home/X/AppData/Local/Temp"
for utr_t in /c/home/x/appdata/local/temp/f C:/home/x/appdata/local/temp/f \
  /C/Home/X/AppData/Local/Temp/ /c/home/x/appdata/local/temp; do
  if utr_stub msys "$UTR_CAND" "$utr_t"; then
    ok "under_temp_root: drive target '$utr_t' matches its temp candidate"
  else
    fail "under_temp_root: drive target '$utr_t' missed its temp candidate"
  fi
done
for utr_t in /c/home/x/appdata/local/tempevil/f C:/Home/x/AppData/Local/TempEvil/f \
  '/c/home/x~1/appdata/local/temp/f' //server/share/home/x/appdata/local/temp/f \
  /d/home/x/appdata/local/temp/f /c/home/x/appdata/local; do
  if utr_stub msys "$UTR_CAND" "$utr_t"; then
    fail "under_temp_root: '$utr_t' wrongly matched the temp candidate"
  else
    ok "under_temp_root: '$utr_t' is not under the temp candidate"
  fi
done
if utr_stub msys C:/tmp /c/tmpx; then
  fail "under_temp_root: /c/tmpx wrongly matched a C:/tmp candidate"
else
  ok "under_temp_root: /c/tmpx is not under a C:/tmp candidate"
fi
if utr_stub msys C:/tmp /c/tmp/x; then
  ok "under_temp_root: /c/tmp/x matches a C:/tmp candidate"
else
  fail "under_temp_root: /c/tmp/x missed a C:/tmp candidate"
fi
if utr_stub msys C:/ /c/anything/f; then
  ok "under_temp_root: drive-root candidate contains a path on its drive"
else
  fail "under_temp_root: drive-root candidate missed a path on its drive"
fi
if utr_stub msys C:/ /d/anything; then
  fail "under_temp_root: drive-root candidate matched another drive"
else
  ok "under_temp_root: drive-root candidate does not contain another drive"
fi
if utr_stub linux-gnu /tmp '/tmp\x'; then
  fail "under_temp_root: POSIX target '/tmp\\x' folded into the /tmp candidate"
else
  ok "under_temp_root: POSIX target '/tmp\\x' is not folded under /tmp"
fi
if utr_stub linux-gnu /tmp /tmp/x; then
  ok "under_temp_root: POSIX target /tmp/x matches the /tmp candidate"
else
  fail "under_temp_root: POSIX target /tmp/x missed the /tmp candidate"
fi
# shellcheck disable=SC2031 # reads the host's real OSTYPE; utr_stub sets it only in its own subshell
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == win32 ]] &&
  command -v cygpath >/dev/null 2>&1 && [[ -d "${TEMP:-}" ]]; then
  utr_temp="$TEMP"
  [[ "$utr_temp" == [A-Za-z]:* ]] || utr_temp=$(cygpath -m "$utr_temp")
  utr_long=$(cygpath -l -m "$utr_temp")
  utr_u=$(cygpath -u "$utr_long")
  utr_u="${utr_u,,}/probe/f"
  # shellcheck disable=SC2030 # subshell-local by design: the override must not leak into the suite
  if (
    export TMPDIR="" TMP="$utr_temp" TEMP="$utr_temp"
    hook::under_temp_root "$utr_u"
  ); then
    ok "under_temp_root: real-host '$utr_u' matches the host temp root"
  else
    fail "under_temp_root: real-host '$utr_u' missed the host temp root (TEMP=$TEMP, as $utr_temp)"
  fi
else
  ok "under_temp_root: Windows drive-spelling case SKIPPED (not a Windows host with cygpath and a TEMP directory; no coverage here, not a pass)"
fi

TW_DIR="$(cd "$HOOK_DIR/.." && pwd -P)/.work/hu-tempwin-$$"
case "$TW_DIR" in
/tmp/* | /var/tmp/*)
  ok "temp_root_candidates: cygpath drive spellings SKIPPED (the checkout sits under temp at $TW_DIR; no coverage here, not a pass)"
  ;;
*)
  mkdir -p "$TW_DIR/bin" "$TW_DIR/posix" "$TW_DIR/long" "$TW_DIR/short~1" "$TW_DIR/mixed"
  {
    printf '#!%s\n' "$BASH"
    cat <<'TWEOF'
printf '%s\n' "$*" >>"$TW_LOG"
[[ -z "${TW_FAIL:-}" ]] || exit 1
long=0
for a in "$@"; do
  case "$a" in
  -l) long=1 ;;
  -m | --) ;;
  *)
    if ((long)); then
      [[ "$a" == "$TW_SHORT" ]] && a=$TW_LONG
    else
      [[ "$a" == "$TW_FROM" ]] && a=$TW_TO
    fi
    printf '%s\n' "$a"
    ;;
  esac
done
TWEOF
  } >"$TW_DIR/bin/cygpath"
  chmod +x "$TW_DIR/bin/cygpath"
  TW_POSIX="$TW_DIR/posix|/tmp"
  [[ -d /var/tmp ]] && TW_POSIX="$TW_POSIX|/var/tmp"
  tw_run() {
    local ostype="$1"
    shift
    : >"$TW_DIR/log"
    # shellcheck disable=SC2016 # $1..$3 are the child's own positional parameters
    env TMPDIR="$TW_DIR/posix" TMP="" TEMP="" TW_LOG="$TW_DIR/log" \
      TW_SHORT="$TW_DIR/short~1" TW_LONG="$TW_DIR/long" "$@" \
      PATH="$TW_DIR/bin:$PATH" "$BASH" -c '
        OSTYPE="$1"
        source "$2"
        hook::_temp_root_candidates
        (IFS="|"; printf "%s\n" "${_HOOK_TEMP_CANDS[*]}")
        hook::_temp_root_candidates
        (IFS="|"; printf "%s\n" "${_HOOK_TEMP_CANDS[*]}")
        _HOOK_UTR_TARGET_PHYSICAL=0
        if hook::under_temp_root "$3"; then echo in; else echo out; fi
      ' _ "$ostype" "$HOOK_DIR/hook-utils.sh" "$TW_DIR/long/f"
    local calls=0 line
    while IFS= read -r line; do calls=$((calls + 1)); done <"$TW_DIR/log"
    printf '%s\n' "$calls"
  }
  tw_case() {
    local label="$1" want="$2" got
    shift 2
    got=$(tw_run "$@")
    got=${got//$'\n'/ }
    if [[ "$got" == "$want" ]]; then
      ok "temp_root_candidates: $label"
    else
      fail "temp_root_candidates: $label: want '$want', got '$got'"
    fi
  }
  TW_83="$TW_POSIX|$TW_DIR/long|$TW_DIR/short~1"
  tw_case "8.3 mixed answer adds long then short, 2 calls then 0" \
    "$TW_83 $TW_83 in 2" msys TW_FROM="$TW_DIR/posix" TW_TO="$TW_DIR/short~1"
  tw_case "cygwin OSTYPE takes the same arm" \
    "$TW_83 $TW_83 in 2" cygwin TW_FROM="$TW_DIR/posix" TW_TO="$TW_DIR/short~1"
  tw_case "mixed answer without ~ adds it with 1 call" \
    "$TW_POSIX|$TW_DIR/mixed $TW_POSIX|$TW_DIR/mixed out 1" msys TW_FROM="$TW_DIR/posix" TW_TO="$TW_DIR/mixed"
  tw_case "a spelling equal to a POSIX candidate is deduped" \
    "$TW_POSIX $TW_POSIX out 1" msys TW_FROM="$TW_DIR/posix" TW_TO=/tmp
  tw_case "a spelling that is not a directory is dropped" \
    "$TW_POSIX $TW_POSIX out 1" msys TW_FROM="$TW_DIR/posix" TW_TO="C:/no/such/dir"
  tw_case "a failing cygpath adds nothing" \
    "$TW_POSIX $TW_POSIX out 3" msys TW_FROM="$TW_DIR/posix" TW_TO="$TW_DIR/long" TW_FAIL=1
  tw_case "a Linux OSTYPE never calls cygpath" \
    "$TW_POSIX $TW_POSIX out 0" linux-gnu TW_FROM="$TW_DIR/posix" TW_TO="$TW_DIR/long"
  : >"$TW_DIR/log"
  # shellcheck disable=SC2016 # $1 is the child's own positional parameter
  tw_nodrive=$(env TMPDIR="$TW_DIR/posix" TMP="" TEMP="" TW_LOG="$TW_DIR/log" TW_FROM="$TW_DIR/posix" TW_TO="$TW_DIR/long" \
    PATH="$TW_DIR/bin:$PATH" "$BASH" -c '
      OSTYPE=msys
      source "$1"
      hook::_temp_root_candidates --no-drive
      (IFS="|"; printf "%s" "${_HOOK_TEMP_CANDS[*]}")
    ' _ "$HOOK_DIR/hook-utils.sh")
  if [[ "$tw_nodrive" == "$TW_POSIX" && ! -s "$TW_DIR/log" ]]; then
    ok "temp_root_candidates: --no-drive adds no spelling and calls no cygpath"
  else
    fail "temp_root_candidates: --no-drive: want '$TW_POSIX' and no call, got '$tw_nodrive' and '$(<"$TW_DIR/log")'"
  fi
  rm -rf "$TW_DIR"
  ;;
esac

unset HOOK_TELEMETRY_SINK 2>/dev/null || true
if hook::telemetry_enabled; then
  fail "telemetry_enabled: sink unset reported enabled"
else
  ok "telemetry_enabled: sink unset → disabled"
fi

HOOK_TELEMETRY_SINK=""
if hook::telemetry_enabled; then
  fail "telemetry_enabled: empty sink reported enabled"
else
  ok "telemetry_enabled: empty sink → disabled"
fi

HOOK_TELEMETRY_SINK="/some/sink.sh"
if hook::telemetry_enabled; then
  ok "telemetry_enabled: non-empty sink → enabled"
else
  fail "telemetry_enabled: non-empty sink reported disabled"
fi
unset HOOK_TELEMETRY_SINK

in14=$'he said "hi" \\ path\nline2\ttab\rcr'
esc=$(hook::json_escape "$in14")
if [[ "$esc" == 'he said \"hi\" \\ path\nline2\ttab\rcr' ]]; then
  ok "json_escape: quote/backslash/newline/tab/cr escaped"
else
  fail "json_escape: got '$esc'"
fi
esc2=$(hook::json_escape $'a\001b\033c')
if [[ "$esc2" == "abc" ]]; then
  ok "json_escape: residual C0 bytes dropped, other bytes kept"
else
  fail "json_escape: wrong residual-C0 handling: $(printf '%q' "$esc2")"
fi
esc14_to=""
hook::json_escape_to esc14_to "$in14"
if [[ "$esc14_to" == "$esc" ]]; then
  ok "json_escape_to: matches print form"
else
  fail "json_escape_to: got '$esc14_to' want '$esc'"
fi

corpus14b=(
  'plain'
  'he said "hi" \ path'
  $'tab\tnl\ncr\rbs\bff\f' # portability-ok: bash ANSI-C backspace byte, not a GNU grep word boundary
  $'esc\033one\001us\037del\177'
  'slash/and é😀 and -- dash'
  ''
)
for s in "${corpus14b[@]}"; do
  want=$(jq -cn --arg s "$s" '$s' | tr -d '\r')
  esc14b=""
  hook::json_escape_jq_to esc14b "$s"
  got="\"$esc14b\""
  if [[ "$got" == "$want" ]]; then
    ok "json_escape_jq_to: matches jq for $(printf '%q' "${s:0:24}")"
  else
    fail "json_escape_jq_to: bash=$got jq=$want"
  fi
done

compact_is() { # <desc> <input> <want>
  local got=""
  if hook::json_compact_to got "$2" && [[ "$got" == "$3" ]]; then
    ok "json_compact_to: $1"
  else
    fail "json_compact_to ($1): got [$got] want [$3]"
  fi
}
compact_refuses() { # <desc> <input>
  local got=""
  if hook::json_compact_to got "$2"; then
    fail "json_compact_to ($1): accepted [$got], must fall back to jq"
  else
    ok "json_compact_to: $1 falls back"
  fi
}
pretty14c=$(jq -n --arg tool Bash --arg subject 'git commit -m "x"' --arg form '' '{tool:$tool,subject:$subject,form:$form,n:[1,2,{a:null,b:true}],e:{},f:[]}')
compact_is "pretty jq -n object" "$pretty14c" "$(jq -c . <<<"$pretty14c" | tr -d '\r')"
compact_is "compact jq -c object is unchanged" '{"tool":"Write","file":"a b.py","findings":["x: [1] {2}"]}' '{"tool":"Write","file":"a b.py","findings":["x: [1] {2}"]}'
compact_is "escaped quotes and backslashes kept verbatim" '{ "p": "C:\\repo\\a \"q\"" }' '{"p":"C:\\repo\\a \"q\""}'
compact_is "empty object" '{}' '{}'
compact_is "integer literals verbatim" '{ "n": -15, "m": 0, "k": 123456789012345 }' '{"n":-15,"m":0,"k":123456789012345}'
compact_refuses "fraction (jq releases render it differently)" '{"k":1.0}'
compact_refuses "exponent" '{"n":-1.5e3}'
compact_refuses "16-digit integer" '{"big":1234567890123456}'
compact_refuses "unicode escape" '{"a":"\u00e9"}'
compact_refuses "escaped slash" '{"a":"x\/y"}'
compact_refuses "raw control byte in a string" "$(printf '{"a":"x\001y"}')"
compact_refuses "array root" '[1,2]'
compact_refuses "trailing comma" '{"a":1,}'
compact_refuses "bad literal" '{"a":tru}'     # spellchecker:disable-line
compact_refuses "split literal" '{"a":tr ue}' # spellchecker:disable-line
compact_refuses "unterminated string" '{"a":"x}'
compact_refuses "invalid escape" '{"a":"x\qy"}'
compact_refuses "trailing backslash escape" '{"a":"x\\\"}'
compact_refuses "bad \\u hex digits" '{"a":"\uZZZZ"}'
compact_is "nested containers" '{"a":[1,"s",{"b":[]},[[]]],"c":{"d":{}}}' '{"a":[1,"s",{"b":[]},[[]]],"c":{"d":{}}}'
compact_refuses "two scalars" '{"a":1 2}'
compact_refuses "key without colon" '{"a" "b"}'
compact_refuses "array trailing comma" '{"a":[1,]}'
compact_refuses "array leading comma" '{"a":[,1]}'
compact_refuses "two objects in a value" '{"a":{"b":1}{"c":2}}'
compact_refuses "number key" '{1:2}'
compact_refuses "extra close" '{"a":1}}'
compact_refuses "colon in array" '{"a":[1:2]}'
compact_refuses "chained colon" '{"a":"b":"c"}'
compact_refuses "member without value" '{"a":1,"b"}'
compact_refuses "mismatched close" '{"a":[1}]'
compact_refuses "two roots" '{"a":1}{"b":2}'
compact_refuses "root member list" '1,"x":1'
compact_refuses "root closes early" '1},{'
big14c=$(printf '0,%.0s' {1..5000})
compact_refuses "structure past the grammar cap" "{\"a\":[${big14c}0]}"

SINK3B="$(mktemp)"
STUB3B="$(make_sink "cat >\"$SINK3B\"")"
hook_event3b=$'Post\tTool\001Use'
# shellcheck disable=SC2030,SC2031  # subshell-local by design
(
  export HOOK_TELEMETRY_SINK="$STUB3B"
  hook::emit_telemetry "sam\"ple" "$hook_event3b" 'ok é' "$EPOCHREALTIME" "$pretty14c" 2>/dev/null
  wait
)
wait_for_sink "$SINK3B" "$SINK_POLLS" || true
if [[ -s "$SINK3B" ]]; then
  lines3b=$(wc -l <"$SINK3B" | tr -d ' ')
  rerender=$(jq -c . "$SINK3B" 2>/dev/null | tr -d '\r')
  raw=$(tr -d '\r' <"$SINK3B")
  if [[ "$lines3b" == 1 && "$raw" == "$rerender" ]]; then
    ok "envelope: one compact line, byte-identical to jq -c of itself"
  else
    fail "envelope: lines=$lines3b raw=[$raw] jq -c=[$rerender]"
  fi
  if [[ "$raw" == '{"schema_version":"1.1","timestamp":"'*'","hook":"sam\"ple","hook_event":"Post\tTool\u0001Use","status":"ok é","duration_ms":'*',"data":{"tool":"Bash","subject":"git commit -m \"x\"","form":"","n":[1,2,{"a":null,"b":true}],"e":{},"f":[]}}' ]]; then
    ok "envelope: field order, escapes and compacted data are jq's"
  else
    fail "envelope: unexpected bytes: $raw"
  fi
else
  fail "envelope (3b): sink empty"
  fail "envelope (3b): bytes not verifiable"
fi
: >"$SINK3B"
# shellcheck disable=SC2030,SC2031,SC2329  # subshell-local by design; jq is invoked through the lib
(
  jq() {
    echo "fallback invoked jq" >"$SINK3B.err"
    return 127
  }
  export HOOK_TELEMETRY_SINK="$STUB3B"
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"a":"\u00e9"}' 2>/dev/null
  wait
)
if grep -q 'fallback invoked jq' "$SINK3B.err" 2>/dev/null && [[ ! -s "$SINK3B" ]]; then # portability-ok: grep -q quiet match, not grep -P
  ok "envelope: unprovable data falls back to jq (and fails open when jq fails)"
else
  fail "envelope fallback: marker=$(cat "$SINK3B.err" 2>/dev/null) sink=$(cat "$SINK3B")"
fi
: >"$SINK3B"
# shellcheck disable=SC2030,SC2031  # subshell-local by design
(
  export HOOK_TELEMETRY_SINK="$STUB3B"
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"a":"\u00e9"}' 2>/dev/null
  wait
)
wait_for_sink "$SINK3B" "$SINK_POLLS" || true
if [[ "$(jq -r '.data.a' "$SINK3B" 2>/dev/null)" == "é" ]]; then
  ok "envelope: the jq fallback delivers the decoded data"
else
  fail "envelope fallback with jq: $(cat "$SINK3B")"
fi
rm -f "$SINK3B" "$SINK3B.err" "$STUB3B"

fast_is_jq() { # <desc> <payload>
  local got="" rc=0 want
  hook::_fast_file_path_to got "$2" || rc=$?
  want=$(printf '%s' "$2" | jq -r '(.tool_input.file_path // empty) | gsub("\r";"")' 2>/dev/null)
  case "$rc" in
  0) if [[ "$got" == "$want" ]]; then ok "fast file_path: $1 (proven: $(printf '%q' "$got"))"; else fail "fast file_path ($1): got [$got] jq [$want]"; fi ;;
  1) if [[ -z "$want" ]]; then ok "fast file_path: $1 (proven absent)"; else fail "fast file_path ($1): said absent, jq says [$want]"; fi ;;
  2) ok "fast file_path: $1 (falls back to jq)" ;;
  *) fail "fast file_path ($1): rc=$rc" ;;
  esac
}
fast_is_jq "Write payload" '{"session_id":"s","tool_name":"Write","tool_input":{"file_path":"src/app.py","content":"x = {\"a\": [1,2]}\n"},"tool_response":{"filePath":"src/app.py","success":true}}'
fast_is_jq "Edit payload with escapes" '{"tool_input":{"file_path":"C:\\repo\\a \"b\".md","old_string":"a\nb","new_string":"","replace_all":false}}'
fast_is_jq "pretty-printed payload" "$(jq -n '{tool_input:{file_path:"docs/x.md"}}')"
fast_is_jq "ASCII unicode escape in the value" '{"tool_input":{"file_path":"\u0041.md"}}'
fast_is_jq "trailing CR and newline stripped" '{"tool_input":{"file_path":"x.md\r\n"}}'
fast_is_jq "keys spelled with unicode escapes" '{"tool\u005finput":{"file\u005fpath":"esc.md"}}'
fast_is_jq "non-ASCII value" '{"tool_input":{"file_path":"é/日本.md"}}'
fast_is_jq "empty value" '{"tool_input":{"file_path":""}}'
fast_is_jq "top-level file_path only" '{"file_path":"top.md","tool_input":{"content":"y"}}'
fast_is_jq "tool_input nested in another object" '{"outer":{"tool_input":{"file_path":"deep.md"}}}'
fast_is_jq "file_path as a string value, not a key" '{"tool_input":{"content":"x"},"y":"file_path"}'
fast_is_jq "no file_path (Bash payload)" '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
fast_is_jq "two file_path keys" '{"file_path":"top.md","tool_input":{"file_path":"in.md"}}'
fast_is_jq "nested object inside tool_input" '{"tool_input":{"file_path":"in.md","meta":{"a":1}}}'
fast_is_jq "non-string value" '{"tool_input":{"file_path":123}}'
fast_is_jq "non-ASCII unicode escape" '{"tool_input":{"file_path":"\u00e9.md"}}'
fast_is_jq "truncated payload" '{"tool_input":{"file_path":"in.md"},"tool_response":{"filePath'
fast_is_jq "array root" '[{"tool_input":{"file_path":"arr.md"}}]'
fast_is_jq "invalid escape in an unrelated string" '{"tool_input":{"file_path":"in.md"},"z":"a\qb"}'
fast_is_jq "bad \\u hex in an unrelated string" '{"tool_input":{"file_path":"in.md"},"z":"\uZZZZ"}'
rc12g=0
hook::_fast_file_path_to got12g '{"tool_input":{"file_path":"in.md"},"z":"a\qb"}' || rc12g=$?
if [[ "$rc12g" -eq 2 ]]; then
  ok "fast file_path: an invalid escape anywhere in the payload falls back to jq"
else
  fail "fast file_path: invalid escape elsewhere rc=$rc12g got=[${got12g:-}] (want 2)"
fi
rc12g=0
hook::_fast_file_path_to got12g '{"file_path":"top.md","tool_input":{"content":"y"}}' || rc12g=$?
if [[ "$rc12g" -eq 1 ]]; then
  ok "fast file_path: top-level file_path is proven absent, never taken"
else
  fail "fast file_path: top-level file_path rc=$rc12g got=[${got12g:-}]"
fi
printf -v pad12g 'y%.0s' $(seq 1 70000)
big12g="{\"tool_input\":{\"file_path\":\"big.md\",\"content\":\"$pad12g\"}}"
rc12g=0
hook::_fast_file_path_to got12g "$big12g" || rc12g=$?
if ((${#big12g} > 65536)) && [[ "$rc12g" -eq 2 ]]; then
  ok "fast file_path: ${#big12g}-byte payload falls back to jq"
else
  fail "fast file_path: ${#big12g}-byte payload rc=$rc12g (want 2 on a payload over 65536 bytes)"
fi
printf -v pad12g 'y%.0s' $(seq 1 60000)
big12g="{\"tool_input\":{\"file_path\":\"big.md\",\"content\":\"$pad12g\"}}"
rc12g=0
hook::_fast_file_path_to got12g "$big12g" || rc12g=$?
if ((${#big12g} <= 65536)) && [[ "$rc12g" -eq 0 && "$got12g" == "big.md" ]]; then
  ok "fast file_path: ${#big12g}-byte payload under the cap is proven by the fast path"
else
  fail "fast file_path: ${#big12g}-byte payload rc=$rc12g got=[${got12g:-}] (want 0/big.md)"
fi
unset got12g rc12g big12g pad12g

fast_is_jq "raw C1 characters (U+0085, U+009F)" $'{"tool_input":{"file_path":"c1\xc2\x85x.md","content":"\xc2\x9f"}}'
fast_is_jq "emoji and a space in the value" '{"tool_input":{"file_path":"😀/a b.md","content":"🎉"}}'
rc12g2=0
got12g2=""
hook::_fast_file_path_to got12g2 $'{"tool_input":{"file_path":"c1\xc2\x85x.md"}}' || rc12g2=$?
if ((rc12g2 == 0)) && [[ "$got12g2" == $'c1\xc2\x85x.md' ]]; then
  ok "fast file_path: a raw C1 character is proven, not handed to jq"
else
  fail "fast file_path: raw C1 rc=$rc12g2 got=[$(printf '%q' "${got12g2:-}")] (want 0)"
fi
lc12g2_check() { # <label> <command...>
  local label="$1" before_len mb='é日' lc_rc=0
  shift
  before_len=${#mb}
  "$@" >/dev/null 2>&1 || lc_rc=$?
  if ((lc_rc == 127)); then
    fail "C locale check $label: command not run"
  elif [[ "${#mb}" == "$before_len" ]]; then
    ok "C locale restored after $label (rc $lc_rc)"
  else
    fail "C locale leaked after $label: \${#mb} $before_len -> ${#mb}"
  fi
}
lc12g2_ok='{"tool_name":"Edit","tool_input":{"file_path":"a.md","new_string":"é"}}'
lc12g2_bad='{"tool_input":{"file_path":"a.md"},"z":"a\qb"}'
lc12g2_run() {
  lc12g2_check "_fast_file_path_to (proven)" hook::_fast_file_path_to got12g2 "$lc12g2_ok"
  lc12g2_check "_fast_file_path_to (not proven)" hook::_fast_file_path_to got12g2 "$lc12g2_bad"
  if hook::_fast_fields_supported; then
    lc12g2_check "_fast_fields (proven)" hook::_fast_fields "$lc12g2_ok" '.tool_name'
    lc12g2_check "_fast_fields (not proven)" hook::_fast_fields "$lc12g2_bad" '.tool_name'
  fi
  lc12g2_check "json_compact_to" hook::json_compact_to got12g2 '{"a":"é"}'
  lc12g2_check "_json_object_proven" hook::_json_object_proven "$lc12g2_ok"
}
(
  unset LC_ALL
  lc12g2_run
  if [[ -z "${LC_ALL+x}" ]]; then ok "C locale: an unset LC_ALL stays unset"; else fail "C locale: LC_ALL left set to [$LC_ALL]"; fi
)
(
  # shellcheck disable=SC2030
  export LC_ALL=C.UTF-8
  lc12g2_run
  if [[ "$LC_ALL" == C.UTF-8 && "$(declare -p LC_ALL)" == 'declare -x LC_ALL='* ]]; then
    ok "C locale: an exported LC_ALL keeps its value and export flag"
  else
    fail "C locale: LC_ALL came back as [$(declare -p LC_ALL 2>&1)]"
  fi
)
unset rc12g2 got12g2 lc12g2_ok lc12g2_bad

dirname_is() { # <path> <want>
  local got=""
  hook::dirname_to got "$1"
  if [[ "$got" == "$2" ]]; then
    ok "dirname_to: $1 -> $2"
  else
    fail "dirname_to: $1 -> [$got] want [$2]"
  fi
}
dirname_is /a/b/c.md /a/b
dirname_is /c.md /
dirname_is c.md .
dirname_is C:/repo/x.md C:/repo
dirname_is /c/x.md /c

notice=$(hook::emit_skip_notice PostToolUse 'my-plugin: tool "x" missing — skipped')
if jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"
  and (.hookSpecificOutput.additionalContext | contains("missing"))
  and (.systemMessage | contains("missing"))' <<<"$notice" >/dev/null 2>&1; then
  ok "emit_skip_notice: valid JSON with both channels"
else
  fail "emit_skip_notice: bad JSON or missing fields: $notice"
fi
EMPTY15="$(mktemp -d)"
notice_nojq=$(PATH="$EMPTY15" hook::emit_skip_notice PostToolUse "p: jq missing")
rmdir "$EMPTY15" 2>/dev/null || true
if [[ "$notice_nojq" == *'"systemMessage":"p: jq missing"'* ]]; then
  ok "emit_skip_notice: emits without any external binaries"
else
  fail "emit_skip_notice: empty-PATH emission broken: $notice_nojq"
fi
combined=$(hook::emit_channels PostToolUse $'finding line 1\nfinding line 2' 'tool missing — skipped')
if jq -e '(.hookSpecificOutput.additionalContext | contains("finding line 2"))
  and .systemMessage == "tool missing — skipped"' <<<"$combined" >/dev/null 2>&1; then
  ok "emit_channels: combined ctx + sysmsg in one document"
else
  fail "emit_channels: combined shape wrong: $combined"
fi
if [[ -z "$(hook::emit_channels PostToolUse "" "")" ]]; then
  ok "emit_channels: both empty → no output"
else
  fail "emit_channels: emitted with both channels empty"
fi
sysmsg=$(hook::emit_system_message 'notify: jq missing')
if jq -e '.systemMessage == "notify: jq missing" and (has("hookSpecificOutput") | not)' <<<"$sysmsg" >/dev/null 2>&1; then
  ok "emit_system_message: systemMessage-only shape"
else
  fail "emit_system_message: wrong shape: $sysmsg"
fi

DATA16="$(mktemp -d)"
INPUT_S1='{"session_id":"aaaa-1111","hook_event_name":"PostToolUse"}'
INPUT_S2='{"session_id":"bbbb-2222","hook_event_name":"PostToolUse"}'
if (CLAUDE_PLUGIN_DATA="$DATA16" hook::notice_once "k1" "$INPUT_S1"); then
  ok "notice_once: first call emits"
else
  fail "notice_once: first call suppressed"
fi
if (CLAUDE_PLUGIN_DATA="$DATA16" hook::notice_once "k1" "$INPUT_S1"); then
  fail "notice_once: repeat call in same session emitted again"
else
  ok "notice_once: repeat call suppressed"
fi
if (CLAUDE_PLUGIN_DATA="$DATA16" hook::notice_once "k1" "$INPUT_S2"); then
  ok "notice_once: new session emits again"
else
  fail "notice_once: new session suppressed"
fi
if (CLAUDE_PLUGIN_DATA="$DATA16" hook::notice_once "k2" "$INPUT_S1"); then
  ok "notice_once: distinct key emits"
else
  fail "notice_once: distinct key suppressed"
fi
if (
  unset CLAUDE_PLUGIN_DATA 2>/dev/null
  hook::notice_once "k1" "$INPUT_S1"
) &&
  (
    unset CLAUDE_PLUGIN_DATA 2>/dev/null
    hook::notice_once "k1" "$INPUT_S1"
  ); then
  ok "notice_once: no data dir → fail-open emit"
else
  fail "notice_once: no data dir suppressed a notice"
fi
rm -rf "$DATA16"

DATA16C="$(mktemp -d)"
INPUT_AGENT_A='{"session_id":"sess-1","agent_id":"agent-A","hook_event_name":"PostToolUse"}'
INPUT_AGENT_B='{"session_id":"sess-1","agent_id":"agent-B","hook_event_name":"PostToolUse"}'
latch16() {
  local rc=0
  CLAUDE_PLUGIN_DATA="$1" hook::notice_once "$2" "$3" ${4:+"$4"} || rc=$?
  printf '%s %s %s %s' "$rc" "$HOOK_NOTICE_TO_MODEL" "$HOOK_NOTICE_TO_USER" "$HOOK_NOTICE_KIND"
}
got16="$(latch16 "$DATA16C" k1 "$INPUT_AGENT_A")"
if [[ "$got16" == "0 1 1 full" ]]; then
  ok "notice_once: first call for agent A is due on both channels"
else
  fail "notice_once: first call for agent A" "got '$got16'"
fi
got16="$(latch16 "$DATA16C" k1 "$INPUT_AGENT_B")"
if [[ "$got16" == "0 1 0 model" ]]; then
  ok "notice_once: same session, other agent is due on the model channel only"
else
  fail "notice_once: other agent in the same session" "got '$got16'"
fi
got16="$(latch16 "$DATA16C" k1 "$INPUT_AGENT_A")"
if [[ "${got16%% *}" == 1 ]]; then
  ok "notice_once: agent A second call suppressed"
else
  fail "notice_once: agent A second call" "got '$got16'"
fi
DATA16Q="$(mktemp -d)"
quiet16="$(
  CLAUDE_PLUGIN_DATA="$DATA16Q"
  due=0
  for _i in $(seq 1 30); do
    hook::notice_once "k-quiet" "$INPUT_AGENT_A" && due=$((due + 1))
  done
  printf '%s' "$due"
)"
if [[ "$quiet16" == 1 ]]; then
  ok "notice_once: 30 skips in one agent are due once, never renewed"
else
  fail "notice_once: 30 skips in one agent were due $quiet16 times, want 1"
fi
quiet16p="$(
  CLAUDE_PLUGIN_DATA="$DATA16Q"
  due=0
  for _i in $(seq 1 30); do
    hook::notice_once "k-quiet-pre" "$INPUT_AGENT_A" prerequisite && due=$((due + 1))
  done
  printf '%s' "$due"
)"
if [[ "$quiet16p" == 1 ]]; then
  ok "notice_once: a third argument is accepted and changes nothing"
else
  fail "notice_once: 30 prerequisite skips were due $quiet16p times, want 1"
fi
mkdir -p "$DATA16Q/skip-notices"
: >"$DATA16Q/skip-notices/demo-tool.sess-1.user"
got16="$(latch16 "$DATA16Q" demo-tool "$INPUT_AGENT_A")"
if [[ "$got16" == "0 1 0 model" ]]; then
  ok "notice_once: a user marker written at SessionStart leaves only the model due"
else
  fail "notice_once: probe-written user marker" "got '$got16'"
fi
rm -rf "$DATA16C" "$DATA16Q"

split16="$(hook::emit_skip_notice PostToolUse 'model: x' 'user: y')"
if jq -e '.hookSpecificOutput.additionalContext == "model: x" and .systemMessage == "user: y"' \
  <<<"$split16" >/dev/null 2>&1; then
  ok "emit_skip_notice: two texts go one to each channel"
else
  fail "emit_skip_notice: split channels" "got '$split16'"
fi
useronly16="$(hook::emit_skip_notice PostToolUse '' 'user: y')"
if jq -e '.systemMessage == "user: y" and (has("hookSpecificOutput") | not)' <<<"$useronly16" >/dev/null 2>&1; then
  ok "emit_skip_notice: an empty model text sends the user channel only"
else
  fail "emit_skip_notice: user only" "got '$useronly16'"
fi
gated16="$(HOOK_NOTICE_TO_MODEL=1 HOOK_NOTICE_TO_USER=0 hook::emit_skip_notice PostToolUse 'same text')"
if jq -e '.hookSpecificOutput.additionalContext == "same text" and (has("systemMessage") | not)' \
  <<<"$gated16" >/dev/null 2>&1; then
  ok "emit_skip_notice: a channel notice_once did not clear gets the one-argument text alone"
else
  fail "emit_skip_notice: latch-gated channel" "got '$gated16'"
fi
path16_err="$WORK/path16.err"
path16="$(hook::emit_skip_notice PostToolUse $'plugin: tool missing\nPATH probed: /usr/bin:/tmp/x' 2>"$path16_err")"
if jq -e '.hookSpecificOutput.additionalContext == "plugin: tool missing" and .systemMessage == "plugin: tool missing"' \
  <<<"$path16" >/dev/null 2>&1 && [[ "$(<"$path16_err")" == 'PATH probed: /usr/bin:/tmp/x' ]]; then
  ok "emit_skip_notice: a PATH probed line goes to stderr, not to either channel"
else
  fail "emit_skip_notice: PATH line" "got '$path16' stderr '$(cat "$path16_err")'"
fi

cut16_err="$WORK/cut16.err"
cut16="$(hook::stdin_cut_short_notice PreToolUse "guardrails demo" 2>"$cut16_err")"
cut16_want="guardrails demo: hook stdin was cut short, so this tool call ran unchecked. If it recurs, the host is starved; see the stdin_read_timeout option."
if jq -e --arg w "$cut16_want" '.systemMessage == $w and (has("hookSpecificOutput") | not)' <<<"$cut16" >/dev/null 2>&1 &&
  [[ "$(cat "$cut16_err")" == "$cut16_want" ]]; then
  ok "stdin_cut_short_notice: one line to the user and stderr, nothing to the model"
else
  fail "stdin_cut_short_notice" "got '$cut16' stderr '$(cat "$cut16_err")'"
fi

DATA16R="$(mktemp -d)"
race16_probe() {
  CLAUDE_PLUGIN_DATA="$DATA16R" hook::notice_once race "{\"session_id\":\"sess-r\",\"agent_id\":\"agent-$1\"}"
  [[ "$HOOK_NOTICE_TO_USER" == 1 ]] && : >"$DATA16R/user.$1"
  [[ "$HOOK_NOTICE_TO_MODEL" == 1 ]] && : >"$DATA16R/model.$1"
  return 0
}
for i in $(seq 1 12); do race16_probe "$i" & done
wait
shopt -s nullglob
race16_users=("$DATA16R"/user.*)
race16_models=("$DATA16R"/model.*)
shopt -u nullglob
race16_user=${#race16_users[@]}
race16_model=${#race16_models[@]}
if [[ "$race16_user" == 1 && "$race16_model" == 12 ]]; then
  ok "notice_once: racing agents send the user notice once and each its model notice"
else
  fail "notice_once race: want 1 user, 12 model" "got $race16_user user, $race16_model model"
fi
rm -rf "$DATA16R"

DATA16F="$(mktemp -d)"
once_file16() { CLAUDE_PLUGIN_DATA="$DATA16F" hook::once_per_file "$@" && printf 0 || printf 1; }
once_file16_got="$(once_file16 hint "$INPUT_AGENT_A" /r/a.md)$(once_file16 hint "$INPUT_AGENT_A" /r/a.md)$(once_file16 hint "$INPUT_AGENT_A" /r/b.md)"
once_file16_got+="$(once_file16 hint "$INPUT_AGENT_B" /r/a.md)$(once_file16 hint "$INPUT_S1" /r/a.md)$(once_file16 other "$INPUT_AGENT_A" /r/a.md)"
if [[ "$once_file16_got" == "010000" ]]; then
  ok "once_per_file: once per (key, session, agent, file)"
else
  fail "once_per_file: want 010000 (first, repeat, other file, other agent, other session, other key)" "got $once_file16_got"
fi
once_file16_got="$(once_file16 fold "$INPUT_AGENT_A" '/r/x y.md')$(once_file16 fold "$INPUT_AGENT_A" /r/x_y.md)"
if [[ "$once_file16_got" == "00" ]]; then
  ok "once_per_file: paths that fold to one marker name stay distinct"
else
  fail "once_per_file: folded paths" "got $once_file16_got"
fi
rm -rf "$DATA16F"
if (
  unset CLAUDE_PLUGIN_DATA
  hook::once_per_file hint "$INPUT_AGENT_A" /r/a.md && hook::once_per_file hint "$INPUT_AGENT_A" /r/a.md
); then
  ok "once_per_file: no data dir → fail-open, always due"
else
  fail "once_per_file: no data dir suppressed a hint"
fi

if got=$(hook::raw_file_path '{"session_id":"s","tool_input":{"file_path":"src/app.py"},"tool_name":"Write"}') && [[ "$got" == "src/app.py" ]]; then
  ok "raw_file_path: plain path extracted"
else
  fail "raw_file_path: plain path (got '$got')"
fi
if got=$(hook::raw_file_path '{"tool_input":{"file_path":"C:\\repo\\a.yml"}}') && [[ "$got" == 'C:\\repo\\a.yml' ]]; then
  ok "raw_file_path: JSON-escaped Windows path returned escaped"
else
  fail "raw_file_path: escaped path (got '$got')"
fi
if got=$(hook::raw_file_path '{"tool_input":{"file_path":"a \"quoted\" name.md"}}') && [[ "$got" == 'a \"quoted\" name.md' ]]; then
  ok "raw_file_path: escaped quotes inside value survive"
else
  fail "raw_file_path: quoted value (got '$got')"
fi
if hook::raw_file_path '{"tool_name":"Bash","tool_input":{"command":"ls"}}' >/dev/null; then
  fail "raw_file_path: no file_path should return 1"
else
  ok "raw_file_path: absent file_path returns 1"
fi

out17=$( (
  hook::require jq PostToolUse tp '{"session_id":"s"}'
  echo "alive"
) 2>/dev/null)
if [[ "$out17" == "alive" ]]; then
  ok "require: jq present → pass-through"
else
  fail "require: jq present misbehaved: $out17"
fi
make_stub_bin() {
  local d t real_t
  d="$(mktemp -d)"
  for t in mkdir find tr; do
    real_t=$(command -v "$t")
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$d/$t"
    chmod +x "$d/$t"
  done
  printf '%s' "$d"
}

DATA17="$(mktemp -d)"
FAKEBIN17="$(make_stub_bin)"
run17() {
  CLAUDE_PLUGIN_DATA="$DATA17" "$BASH" -c '
    PATH="'"$FAKEBIN17"'"
    source "'"$HOOK_DIR"'/hook-utils.sh"
    hook::require jq PostToolUse tp "{\"session_id\":\"cccc-3333\"}"
    echo "unreachable"
  ' 2>/dev/null
}
first17=$(run17)
rc_first=$?
second17=$(run17)
rc_second=$?
if [[ $rc_first -eq 0 && "$first17" == *'"systemMessage"'* && "$first17" != *unreachable* ]]; then
  ok "require: jq absent → visible notice + exit 0"
else
  fail "require: first run rc=$rc_first out=$first17"
fi
if [[ $rc_second -eq 0 && "$second17" != *'"systemMessage"'* && "$second17" != *unreachable* ]]; then
  ok "require: second run same session → silent exit 0"
else
  fail "require: second run rc=$rc_second out=$second17"
fi
rm -rf "$DATA17" "$FAKEBIN17"

FAKEBIN17="$(make_stub_bin)"
ROOT17="$(mktemp -d)/cache/market/demo-plug/1.2.3"
mkdir -p "$ROOT17"
cat >"$ROOT17/prerequisites.json" <<'JSON'
{
  "requires": [
    {
      "id": "node",
      "kind": "runtime",
      "degrade": "Without node, nothing runs.",
      "install": { "docs": "https://example.invalid/node" },
      "check": "/demo-plug:check-node"
    },
    {
      "id": "jq",
      "kind": "cli",
      "need": "required",
      "for": ["hook:demo.sh"],
      "degrade": "Without jq, the \"demo\" hook is skipped.",
      "install": { "docs": "https://example.invalid/jq", "brew": "jq" },
      "check": "/demo-plug:check"
    }
  ]
}
JSON
require17() {
  local root="$1" id="${2:-jq}" data="${3:-}"
  [[ -n "$data" ]] || data="$(mktemp -d "$WORK/data17r.XXXXXX")"
  CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PLUGIN_DATA="$data" "$BASH" -c '
    PATH="'"$FAKEBIN17"'"
    source "'"$HOOK_DIR"'/hook-utils.sh"
    hook::require '"$id"' PostToolUse tp "{\"session_id\":\"dddd-4444\",\"agent_id\":\"'"${4:-main}"'\"}"
  ' 2>/dev/null
}
cmd17="node \"$ROOT17/lib/prerequisites.mjs\" check \"$ROOT17\""
model17='tp: jq not on the hook PATH. Without jq, the "demo" hook is skipped. No further notice this session; diagnose with: '"$cmd17"
user17='tp: jq not on the hook PATH. Without jq, the "demo" hook is skipped. Install (docs: https://example.invalid/jq; brew: jq). Hooks read Claude Code'"'"'s PATH, not your shell profile. No further notice this session; diagnose with: '"$cmd17"
declared17=$(require17 "$ROOT17")
if jq -e --arg m "$model17" --arg u "$user17" \
  '.hookSpecificOutput.additionalContext == $m and .systemMessage == $u' <<<"$declared17" >/dev/null 2>&1; then
  ok "require: model and user lines from the declared degrade, install map and check command"
else
  fail "require: declared entry notice" "got $declared17"
fi
req17_err="$(CLAUDE_PLUGIN_ROOT="$ROOT17" CLAUDE_PLUGIN_DATA="" "$BASH" -c '
  PATH="'"$FAKEBIN17"'"
  source "'"$HOOK_DIR"'/hook-utils.sh"
  hook::require jq PreToolUse tp "{\"session_id\":\"eeee-5555\"}"
' 2>&1 >/dev/null)"
if [[ -z "$req17_err" ]]; then
  ok "require: nothing on stderr (no PATH line)"
else
  fail "require: stderr" "got '$req17_err'"
fi
DATA17S="$(mktemp -d "$WORK/data17s.XXXXXX")"
require17 "$ROOT17" jq "$DATA17S" main >/dev/null
sub17=$(require17 "$ROOT17" jq "$DATA17S" sub-1)
if jq -e --arg m "$model17" '.hookSpecificOutput.additionalContext == $m and (has("systemMessage") | not)' \
  <<<"$sub17" >/dev/null 2>&1; then
  ok "require: a subagent's first skip tells the model only; the user was told"
else
  fail "require: subagent first skip" "got $sub17"
fi
again17=$(require17 "$ROOT17" jq "$DATA17S" main)
if [[ -z "$again17" ]]; then
  ok "require: a later skip in the same agent is silent"
else
  fail "require: later skip" "got $again17"
fi
rm "$ROOT17/prerequisites.json"
generic17=$(require17 "$ROOT17")
if [[ "$generic17" == *'tp: jq not on the hook PATH. The hook skips its work.'* &&
  "$generic17" == *"diagnose with: ${cmd17//\"/\\\"}\""* && "$generic17" != *:check* ]]; then
  ok "require: no declared entry → generic text and the checker command from the plugin root"
else
  fail "require: generic notice: $generic17"
fi
mkdir -p "$ROOT17/skills/check-prerequisites"
colliding17=$(require17 "$ROOT17")
if [[ "$colliding17" != *:check* ]]; then
  ok "require: a plugin shipping check-prerequisites names no skill either"
else
  fail "require: check-prerequisites notice: $colliding17"
fi
rm -rf "$ROOT17" "$FAKEBIN17" "$DATA17S"

ROOT17A="$(mktemp -d)/demo-fmt"
mkdir -p "$ROOT17A"
cat >"$ROOT17A/prerequisites.json" <<'JSON'
{
  "requires": [
    {
      "id": "biome",
      "kind": "cli",
      "need": "required",
      "for": ["hook:demo.sh"],
      "detect": { "any": ["biome"], "local_bin": ["node_modules/.bin/biome"] },
      "degrade": "Without biome, edits are not formatted.",
      "install": { "npm": "npm i -D @biomejs/biome" },
      "check": "/demo-fmt:check"
    }
  ]
}
JSON
prereq17() {
  local data="$1"
  shift
  (
    CLAUDE_PLUGIN_ROOT="$ROOT17A"
    CLAUDE_PLUGIN_DATA="$data"
    m="" u="" rc=0
    hook::prereq_notice_to m u biome '{"session_id":"s17a","agent_id":"a1"}' "$@" 2>/dev/null || rc=$?
    printf '%s\n%s\n%s' "$rc" "$m" "$u"
  )
}
DATA17A="$(mktemp -d)"
prereq17_got="$(prereq17 "$DATA17A")"
cmd17a="node \"$ROOT17A/lib/prerequisites.mjs\" check \"$ROOT17A\""
prereq17_want=$'0\ndemo-fmt: biome not on the hook PATH or at node_modules/.bin/biome. Without biome, edits are not formatted. No further notice this session; diagnose with: '"$cmd17a"$'\n'
prereq17_want+="demo-fmt: biome not on the hook PATH or at node_modules/.bin/biome. Without biome, edits are not formatted. Install (npm: npm i -D @biomejs/biome). Hooks read Claude Code's PATH, not your shell profile. No further notice this session; diagnose with: $cmd17a"
if [[ "$prereq17_got" == "$prereq17_want" ]]; then
  ok "prereq_notice_to: the local_bin path joins the where-phrase; the latch key is <plugin>-<id>"
else
  fail "prereq_notice_to: default texts" "got '$prereq17_got'"
fi
mkdir -p "$ROOT17A/lib" "$ROOT17A/nodebin"
cp "$HOOK_DIR/prerequisites.mjs" "$ROOT17A/lib/"
ln -s "$(command -v node)" "$ROOT17A/nodebin/node"
run17a_out="$(cd "$ROOT17A" && PATH="$ROOT17A/nodebin" "$BASH" -c "${prereq17_got##*diagnose with: }")"
run17a_rc=$?
if [[ $run17a_rc -eq 1 && "$run17a_out" == 'FAIL  biome (cli, required): '* ]]; then
  ok "prereq_notice_to: the printed command runs as written and reports biome as FAIL"
else
  fail "prereq_notice_to: printed command" "rc=$run17a_rc out=$run17a_out"
fi
if [[ -f "$DATA17A/skip-notices/demo-fmt-biome.s17a.user" && -f "$DATA17A/skip-notices/demo-fmt-biome.s17a.a1" ]]; then
  ok "prereq_notice_to: latches on the key prerequisites.mjs probe writes"
else
  fail "prereq_notice_to: latch key" "$(ls "$DATA17A/skip-notices" 2>&1)"
fi
prereq17_got="$(prereq17 "$DATA17A")"
if [[ "$prereq17_got" == 1 ]]; then
  ok "prereq_notice_to: not due again in the same agent → 1 and empty texts"
else
  fail "prereq_notice_to: second call" "got '$prereq17_got'"
fi
rm -rf "$DATA17A"
DATA17A="$(mktemp -d)"
prereq17_got="$(prereq17 "$DATA17A" --label demo-hook --where 'not found by the probe' --install 'Install it in the repository: npm i -D x.')"
if [[ "$prereq17_got" == $'0\ndemo-hook: biome not found by the probe. '* &&
  "$prereq17_got" == *$'\ndemo-hook: biome not found by the probe. Without biome, edits are not formatted. Install it in the repository: npm i -D x. Hooks read'* &&
  -f "$DATA17A/skip-notices/demo-hook-biome.s17a.user" ]]; then
  ok "prereq_notice_to: --label, --where and --install override the defaults"
else
  fail "prereq_notice_to: overrides" "got '$prereq17_got'"
fi
prereq17_err() { # the stderr of one due call
  local m u
  {
    CLAUDE_PLUGIN_ROOT="$ROOT17A" CLAUDE_PLUGIN_DATA="" PATH="/x/bin:$PATH" \
      hook::prereq_notice_to m u biome '{"session_id":"s17e"}' "$@" >/dev/null
  } 2>&1
}
if [[ "$(prereq17_err)" == "PATH probed: /x/bin:"* && -z "$(prereq17_err --no-path)" ]]; then
  ok "prereq_notice_to: the PATH goes to stderr, and --no-path keeps it off"
else
  fail "prereq_notice_to: PATH line" "default='$(prereq17_err)' no-path='$(prereq17_err --no-path)'"
fi
rm -rf "$DATA17A" "${ROOT17A%/*}"

out17b=$( (
  hook::require_jq_blocking test-hook block_test_enabled
  echo "alive"
) 2>/dev/null)
if [[ "$out17b" == "alive" ]]; then
  ok "require_jq_blocking: jq present → pass-through"
else
  fail "require_jq_blocking: jq present misbehaved: $out17b"
fi
FAKEBIN17="$(make_stub_bin)"
run17b() {
  local args="$1"
  CLAUDE_PLUGIN_DATA="$(mktemp -d "$WORK/data17b.XXXXXX")" "$BASH" -c '
    PATH="'"$FAKEBIN17"'"
    source "'"$HOOK_DIR"'/hook-utils.sh"
    hook::require_jq_blocking '"$args"'
    echo "unreachable"
  ' 2>&1
}
want17b='BLOCKED: jq is not on PATH, so test-hook cannot read the command and denies every Bash and PowerShell call. Ask the user to install jq (https://jqlang.org/download/).'
with_opt17b=$(run17b 'test-hook block_test_enabled')
rc_with_opt17b=$?
if [[ $rc_with_opt17b -eq 2 && "$with_opt17b" == "$want17b" ]]; then
  ok "require_jq_blocking: jq absent → exit 2 with one line and no kill-switch name"
else
  fail "require_jq_blocking: with option rc=$rc_with_opt17b out=$with_opt17b"
fi
no_opt17b=$(run17b 'test-hook')
rc_no_opt17b=$?
if [[ $rc_no_opt17b -eq 2 && "$no_opt17b" == "$want17b" ]]; then
  ok "require_jq_blocking: jq absent without option → the same line"
else
  fail "require_jq_blocking: without option rc=$rc_no_opt17b out=$no_opt17b"
fi
rm -rf "$FAKEBIN17"

ft17=""
hook::findings_to ft17 "demo: a.py has findings:" $'1:1 E1 one\n\n2:2 E2 two'
if [[ "$ft17" == $'demo: a.py has findings:\n  1:1 E1 one\n  2:2 E2 two' ]]; then
  ok "findings_to: heading plus one indented line per non-empty line"
else
  fail "findings_to: plain report" "got '$ft17'"
fi
FIVE17=$'L1\nL2\nL3\nL4\nL5'
hook::findings_to ft17 "h:" "$FIVE17" --max 2 --more "raise demo_max_findings"
if [[ "$ft17" == $'h:\n  L1\n  L2\n  ... and 3 more (raise demo_max_findings)' ]]; then
  ok "findings_to --max: keeps the first N lines and counts the rest"
else
  fail "findings_to --max" "got '$ft17'"
fi
hook::findings_to ft17 "h:" "$FIVE17" --max 5
if [[ "$ft17" == $'h:\n  L1\n  L2\n  L3\n  L4\n  L5' ]]; then
  ok "findings_to --max: a set at the cap has no more-line"
else
  fail "findings_to --max at the cap" "got '$ft17'"
fi
ft17_fd=""
HOOK_TELEMETRY_SINK="$WORK/sink17c" hook::findings_to ft17 "h:" "$FIVE17" ft17_fd --max 2
if jq -e '. == ["L1","L2","L3","L4","L5"]' <<<"$ft17_fd" >/dev/null 2>&1; then
  ok "findings_to --max: data.findings keeps all five findings"
else
  fail "findings_to --max: data.findings" "got '$ft17_fd'"
fi

DATA17C="$(mktemp -d)"
IN17C_A='{"session_id":"s17c","agent_id":"a1","hook_event_name":"PostToolUse"}'
IN17C_B='{"session_id":"s17c","agent_id":"a2","hook_event_name":"PostToolUse"}'
delta17() { # delta17 <input> <file> <output> [opts...] → the report, or "<none>"
  local in="$1" file="$2" out="$3" r=""
  shift 3
  CLAUDE_PLUGIN_DATA="$DATA17C" hook::findings_to r "demo: $file:" "$out" "$@" --delta "$in" "$file"
  printf '%s' "${r:-<none>}"
}
SET1=$'3:8 F401 os unused\n10:5 E741 name l'
SET2=$'3:8 F401 os unused'
d17="$(delta17 "$IN17C_A" /r/a.py "$SET1")"
if [[ "$d17" == $'demo: /r/a.py:\n  3:8 F401 os unused\n  10:5 E741 name l' ]]; then
  ok "findings_to --delta: the first report is sent"
else
  fail "findings_to --delta: first report" "got '$d17'"
fi
d17="$(delta17 "$IN17C_A" /r/a.py "$SET1")$(delta17 "$IN17C_A" /r/a.py "$SET1")"
if [[ "$d17" == "<none><none>" ]]; then
  ok "findings_to --delta: an unchanged set sends nothing"
else
  fail "findings_to --delta: unchanged set" "got '$d17'"
fi
d17="$(delta17 "$IN17C_B" /r/a.py "$SET1")"
if [[ "$d17" == "demo: /r/a.py:"* ]]; then
  ok "findings_to --delta: another agent is sent the set"
else
  fail "findings_to --delta: other agent" "got '$d17'"
fi
d17="$(delta17 "$IN17C_A" /r/b.py "$SET1")"
if [[ "$d17" == "demo: /r/b.py:"* ]]; then
  ok "findings_to --delta: another file is sent its set"
else
  fail "findings_to --delta: other file" "got '$d17'"
fi
d17="$(delta17 "$IN17C_A" /r/a.py "$SET2")"
if [[ "$d17" == $'demo: /r/a.py:\n  3:8 F401 os unused' ]]; then
  ok "findings_to --delta: a changed set is sent"
else
  fail "findings_to --delta: changed set" "got '$d17'"
fi
d17="$(delta17 "$IN17C_A" /r/a.py "$SET2" --max 1)"
if [[ "$d17" == "demo: /r/a.py:"* ]]; then
  ok "findings_to --delta: the same set under another --max is sent"
else
  fail "findings_to --delta: --max is part of the record" "got '$d17'"
fi
d17="$(delta17 "$IN17C_A" /r/a.py "")"
d17+="|$(delta17 "$IN17C_A" /r/a.py "$SET2" --max 1)"
if [[ "$d17" == $'<none>|demo: /r/a.py:\n  3:8 F401 os unused' ]]; then
  ok "findings_to --delta: a clean run sends nothing and clears the record"
else
  fail "findings_to --delta: clean then same set" "got '$d17'"
fi
ft17_fd=""
CLAUDE_PLUGIN_DATA="$DATA17C" HOOK_TELEMETRY_SINK="$WORK/sink17c" \
  hook::findings_to ft17 "h:" "$SET2" ft17_fd --max 1 --delta "$IN17C_A" /r/a.py
if [[ -z "$ft17" ]] && jq -e '. == ["3:8 F401 os unused"]' <<<"$ft17_fd" >/dev/null 2>&1; then
  ok "findings_to --delta: data.findings is written when the report is suppressed"
else
  fail "findings_to --delta: suppressed data.findings" "ctx='$ft17' fd='$ft17_fd'"
fi
CLAUDE_PLUGIN_DATA="$DATA17C" hook::findings_digest_reset '{"session_id":"s17c","source":"startup"}'
d17="$(delta17 "$IN17C_A" /r/a.py "$SET2" --max 1)"
if [[ "$d17" == "<none>" ]]; then
  ok "findings_digest_reset: a startup SessionStart keeps the records"
else
  fail "findings_digest_reset: startup" "got '$d17'"
fi
for src17 in compact clear; do
  CLAUDE_PLUGIN_DATA="$DATA17C" hook::findings_digest_reset '{"session_id":"s17c","source":"'"$src17"'"}'
  d17="$(delta17 "$IN17C_A" /r/a.py "$SET2" --max 1)$(delta17 "$IN17C_B" /r/a.py "$SET1")"
  if [[ "$d17" == "demo: /r/a.py:"*"demo: /r/a.py:"* ]]; then
    ok "findings_digest_reset: a $src17 SessionStart clears every agent's records"
  else
    fail "findings_digest_reset: $src17" "got '$d17'"
  fi
done
rm -rf "$DATA17C"

join_a() {
  local IFS='|'
  echo "$*"
}

hook::git_resolve_subcommand 0 git -c foo.bar=baz --config-env=alias.c=AVAR c
if [[ "$(join_a "${HOOK_GIT_CONFIG_VALUES[@]}")" == "foo.bar=baz|alias.c=AVAR" &&
"$(join_a "${HOOK_GIT_CONFIG_VALUE_KINDS[@]}")" == "inline|env" ]]; then
  ok "git config: =-forms tag inline vs env"
else
  fail "git config kinds (=-forms): values=($(join_a "${HOOK_GIT_CONFIG_VALUES[@]}")) kinds=($(join_a "${HOOK_GIT_CONFIG_VALUE_KINDS[@]}"))"
fi

hook::git_resolve_subcommand 0 git -c a.b=c --config-env alias.d=AVAR d
if [[ "$(join_a "${HOOK_GIT_CONFIG_VALUE_KINDS[@]}")" == "inline|env" ]]; then
  ok "git config: two-word forms tag inline vs env"
else
  fail "git config kinds (two-word): kinds=($(join_a "${HOOK_GIT_CONFIG_VALUE_KINDS[@]}"))"
fi

hook::git_resolve_subcommand 0 git -c alias.rh='reset --hard' rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 0)) && [[ "$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")" == "reset --hard" ]]; then
  ok "git alias: inline -c alias returns the literal expansion (rc 0)"
else
  fail "git alias (inline): rc=$rc exps=[$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")]"
fi

hook::git_resolve_subcommand 0 git --config-env=alias.rh=AVAR rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 2)); then
  ok "git alias: --config-env alias for the invoked sub is refused by shape (rc 2)"
else
  fail "git alias (env refuse): rc=$rc"
fi

hook::git_resolve_subcommand 0 git -c foo.bar=baz rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 1)); then
  ok "git alias: no alias for the invoked sub returns 1"
else
  fail "git alias (none): rc=$rc"
fi

hook::git_resolve_subcommand 0 git --config-env=core.pager=PAGERVAR status
hook::git_alias_expansion status
rc=$?
if ((rc == 1)); then
  ok "git alias: --config-env non-alias key is not refused (resolvable/allowed)"
else
  fail "git alias (non-alias key): rc=$rc"
fi

hook::git_resolve_subcommand 0 git --config-env=alias.foo=AVAR status
hook::git_alias_expansion status
rc=$?
if ((rc == 1)); then
  ok "git alias: --config-env alias for an uninvoked subcommand is not refused"
else
  fail "git alias (uninvoked alias): rc=$rc"
fi

hook::git_resolve_subcommand 0 git -c alias.rh=status --config-env=alias.rh=AVAR rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 2)); then
  ok "git alias: env value last-wins over an inline decoy -> refuse"
else
  fail "git alias (env last): rc=$rc"
fi

hook::git_resolve_subcommand 0 git --config-env=alias.rh=AVAR -c alias.rh=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 0)) && [[ "$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")" == "status" ]]; then
  ok "git alias: inline value last-wins over an earlier env -> resolve (allowed)"
else
  fail "git alias (inline last): rc=$rc exps=[$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")]"
fi

hook::git_resolve_subcommand 0 git --config-env=alias.RH=AVAR rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 2)); then
  ok "git alias: --config-env key match folds case"
else
  fail "git alias (case fold): rc=$rc"
fi

hook::git_resolve_subcommand 0 git -c alias.rh.command='reset --hard' rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 0)) && [[ "$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")" == "reset --hard" ]]; then
  ok "git alias: inline -c .command subkey returns the literal expansion (rc 0)"
else
  fail "git alias (inline .command): rc=$rc exps=[$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")]"
fi

hook::git_resolve_subcommand 0 git --config-env=alias.rh.command=AVAR rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 2)); then
  ok "git alias: --config-env .command subkey for the invoked sub is refused by shape (rc 2)"
else
  fail "git alias (env .command): rc=$rc"
fi

hook::git_resolve_subcommand 0 git -c alias.rh.nope=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 1)); then
  ok "git alias: a non-command alias subkey is not treated as an alias (rc 1)"
else
  fail "git alias (.nope control): rc=$rc"
fi

hook::git_resolve_subcommand 0 git -c alias.rh.command='reset --hard' -c alias.rh.command=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 0)) && [[ "$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")" == "status" ]]; then
  ok "git alias: last value within the .command spelling wins"
else
  fail "git alias (.command within last): rc=$rc exps=[$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")]"
fi

hook::git_resolve_subcommand 0 git -c alias.rh='reset --hard' -c alias.rh.command=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 0)) && [[ "$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")" == "reset --hard|status" ]]; then
  ok "git alias: dangerous plain + benign .command exposes both expansions (union)"
else
  fail "git alias (union plain+cmd): rc=$rc exps=[$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")]"
fi

hook::git_resolve_subcommand 0 git -c alias.rh=status -c alias.rh.command='reset --hard' rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 0)) && [[ "$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")" == "status|reset --hard" ]]; then
  ok "git alias: benign plain + dangerous .command exposes both expansions (union)"
else
  fail "git alias (union cmd danger): rc=$rc exps=[$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")]"
fi

hook::git_resolve_subcommand 0 git --config-env=alias.rh=AVAR -c alias.rh.command=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 2)); then
  ok "git alias: env plain spelling refuses despite a benign inline .command sibling"
else
  fail "git alias (env plain masked): rc=$rc"
fi

hook::git_resolve_subcommand 0 git --config-env=alias.rh.command=AVAR -c alias.rh=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 2)); then
  ok "git alias: env .command spelling refuses despite a benign inline plain sibling"
else
  fail "git alias (env .command masked): rc=$rc"
fi

gitinv_result() {
  hook::git_invocation "$@"
  local rc=$?
  printf 'rc=%s gi=%s words=[%s] dirs=[%s] sub=%s sub_idx=%s cfg=[%s] kinds=[%s] alias=%s exps=[%s]' \
    "$rc" "$HOOK_GITINV_GI" \
    "$(join_a ${HOOK_GITINV_WORDS[@]+"${HOOK_GITINV_WORDS[@]}"})" \
    "$(join_a ${HOOK_GITINV_WRAPPER_DIRS[@]+"${HOOK_GITINV_WRAPPER_DIRS[@]}"})" \
    "$HOOK_GITINV_SUB" "$HOOK_GITINV_SUB_IDX" \
    "$(join_a ${HOOK_GITINV_CONFIG_VALUES[@]+"${HOOK_GITINV_CONFIG_VALUES[@]}"})" \
    "$(join_a ${HOOK_GITINV_CONFIG_KINDS[@]+"${HOOK_GITINV_CONFIG_KINDS[@]}"})" \
    "$HOOK_GITINV_ALIAS_TERM" \
    "$(join_a ${HOOK_GITINV_ALIAS_EXPS[@]+"${HOOK_GITINV_ALIAS_EXPS[@]}"})"
}

gitinv_is() {
  local desc="$1" want="$2"
  shift 2
  local got
  got="$(gitinv_result "$@")"
  if [[ "$got" == "$want" ]]; then
    ok "git_invocation: $desc"
  else
    fail "git_invocation ($desc):
  want: $want
  got:  $got"
  fi
}

gitinv_is "sudo -D <dir> git push --force" \
  "rc=0 gi=3 words=[sudo|-D|d|git|push|--force] dirs=[d] sub=push sub_idx=4 cfg=[] kinds=[] alias=none exps=[]" \
  sudo -D d git push --force
gitinv_is "env -S splices the operand and reports env's own chdir" \
  "rc=0 gi=2 words=[-C|d|git|push|--force] dirs=[d] sub=push sub_idx=3 cfg=[] kinds=[] alias=none exps=[]" \
  env -S '-C d git push --force'
gitinv_is "env -u swallows -C, so no chdir is reported" \
  "rc=0 gi=3 words=[env|-u|-C|git|status] dirs=[] sub=status sub_idx=4 cfg=[] kinds=[] alias=none exps=[]" \
  env -u -C git status
gitinv_is "git -c core.hooksPath=x commit tags the value inline" \
  "rc=0 gi=0 words=[git|-c|core.hooksPath=x|commit] dirs=[] sub=commit sub_idx=3 cfg=[core.hooksPath=x] kinds=[inline] alias=none exps=[]" \
  git -c core.hooksPath=x commit
gitinv_is "git --config-env=core.hooksPath=VAR commit tags the value env" \
  "rc=0 gi=0 words=[git|--config-env=core.hooksPath=VAR|commit] dirs=[] sub=commit sub_idx=2 cfg=[core.hooksPath=VAR] kinds=[env] alias=none exps=[]" \
  git --config-env=core.hooksPath=VAR commit
gitinv_is "an inline alias whose expansion is a ! shell alias" \
  "rc=0 gi=0 words=[git|-c|alias.p=!git push --force|p] dirs=[] sub=p sub_idx=3 cfg=[alias.p=!git push --force] kinds=[inline] alias=inline exps=[!git push --force]" \
  git -c 'alias.p=!git push --force' p
gitinv_is "a --config-env alias for the invoked subcommand terminates unverifiable" \
  "rc=0 gi=0 words=[git|--config-env=alias.p=AVAR|p] dirs=[] sub=p sub_idx=2 cfg=[alias.p=AVAR] kinds=[env] alias=config-env exps=[]" \
  git --config-env=alias.p=AVAR p
gitinv_is "no git at the command position returns 1" \
  "rc=1 gi=-1 words=[] dirs=[] sub= sub_idx=-1 cfg=[] kinds=[] alias=none exps=[]" \
  ls -la
gitinv_is "git with globals but no subcommand returns 2" \
  "rc=2 gi=0 words=[git|--version] dirs=[] sub= sub_idx=-1 cfg=[] kinds=[] alias=none exps=[]" \
  git --version

gitinv_shell_c_sub=""
gitinv_shell_c_cb() {
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" gitinv_shell_c_cb
    return 0
  fi
  hook::git_invocation "$@" || return 0
  gitinv_shell_c_sub="$HOOK_GITINV_SUB @$HOOK_GITINV_SUB_IDX of [$(join_a ${HOOK_GITINV_WORDS[@]+"${HOOK_GITINV_WORDS[@]}"})]"
}
hook::bash_parse_segments "bash -lc 'git commit --no-verify'" gitinv_shell_c_cb
if [[ "$gitinv_shell_c_sub" == "commit @1 of [git|commit|--no-verify]" ]]; then
  ok "git_invocation: bash -lc operand re-parses into a resolved invocation"
else
  fail "git_invocation (bash -lc operand): got [$gitinv_shell_c_sub]"
fi

wsl_operand_is() {
  local desc="$1" want="$2" got
  shift 2
  HOOK_SHELL_C_OPERAND=""
  if hook::shell_c_operand "$@"; then got="rc=0 [$HOOK_SHELL_C_OPERAND]"; else got="rc=1"; fi
  if [[ "$got" == "$want" ]]; then ok "shell_c_operand (wsl): $desc"; else fail "shell_c_operand (wsl): $desc: want [$want] got [$got]"; fi
}
wsl_operand_is "default shell gets the command line" "rc=0 [git reset --hard]" wsl git reset --hard
wsl_operand_is "a bare metacharacter word reaches the shell bare" "rc=0 [echo x > f]" wsl echo x '>' f
wsl_operand_is "a word with whitespace is double-quoted" "rc=0 [\"git status && git clean -fd\"]" wsl 'git status && git clean -fd'
wsl_operand_is "a nested -c operand keeps its quotes" "rc=0 [bash -c \"echo x > a.txt\"]" wsl bash -c 'echo x > a.txt'
wsl_operand_is "an embedded quote is backslash-escaped" "rc=0 [echo \"a \\\"b\\\" c\"]" wsl echo 'a "b" c'
wsl_operand_is "a trailing backslash run is doubled" "rc=0 [echo \"a\\ b\\\\\"]" wsl echo "a\\ b\\"
wsl_operand_is "an empty word is a pair of quotes" "rc=0 [echo \"\"]" wsl echo ''
wsl_operand_is "run options are stepped over" "rc=0 [git push]" WSL.EXE -d Ubuntu -u root --cd / --distribution-id x --system git push
wsl_operand_is "a leading ~ and GUID are stripped" "rc=0 [git push]" wsl '{01234567-89ab-cdef-0123-456789abcdef}' '~' git push
wsl_operand_is "-- ends the options" "rc=0 [-x git push]" /mnt/c/Windows/System32/wsl.exe -- -x git push
wsl_operand_is "-e keeps argv words literal" "rc=0 [git commit -m 'a; b' 'it'\\''s']" wsl -e git commit -m 'a; b' "it's"
wsl_operand_is "--shell-type none is argv" "rc=0 [echo '>' x]" wsl --shell-type none echo '>' x
wsl_operand_is "--shell-type login is the shell" "rc=0 [echo > x]" wsl --shell-type login echo '>' x
wsl_operand_is "a management verb runs no command line" "rc=1" wsl --list --verbose
wsl_operand_is "an unknown option is stepped over" "rc=0 [git reset --hard]" wsl --bogus git reset --hard
wsl_operand_is "a bare wsl runs no command line" "rc=1" wsl
wsl_operand_is "a word merely starting with wsl is not wsl" "rc=1" wslpath -w /tmp

edir_is() {
  local desc="$1" want="$2"
  shift 2
  local got
  hook::git_effective_dir_to got "$@"
  if [[ "$got" == "$want" ]]; then
    ok "git_effective_dir_to: $desc"
  else
    fail "git_effective_dir_to ($desc): want [$want] got [$got]"
  fi
}
gitinv_saved_base="${HOOK_EFFECTIVE_BASE-}"
HOOK_EFFECTIVE_BASE=/base
edir_is "an option set with no -C leaves the base" /base --git-dir /elsewhere
edir_is "a relative -C joins the base" /base/sub -C sub
edir_is "an absolute -C replaces it" /abs -C sub -C /abs
edir_is "several -C compose left to right" /base/a/b -C a -C b
edir_is "a drive-letter path replaces" 'C:/x' -C 'C:/x'
edir_is "a trailing -C with no operand composes nothing" /base -C

gitinv_reparse_words=()
gitinv_reparse_cb() { gitinv_reparse_words=("$@"); }
# shellcheck disable=SC2016  # the literal `$notvar` is the row: it must stay text
gitinv_reparse_args=('two words' '$notvar' 'a"b')
gitinv_reparse=""
hook::git_alias_reparse_to gitinv_reparse '!git push' "${gitinv_reparse_args[@]}"
hook::bash_parse_segments "$gitinv_reparse" gitinv_reparse_cb
# shellcheck disable=SC2016  # same literal on the expected side
if [[ "$(join_a ${gitinv_reparse_words[@]+"${gitinv_reparse_words[@]}"})" == 'git|push|two words|$notvar|a"b' ]]; then
  ok "git_alias_reparse_to: trailing arguments round-trip through the tokenizer"
else
  fail "git_alias_reparse_to: got [$(join_a ${gitinv_reparse_words[@]+"${gitinv_reparse_words[@]}"})]"
fi

ignores_is() {
  local sub="$1" want="$2" rc=0
  hook::git_subcommand_ignores_alias "$sub" || rc=$?
  if ((rc == want)); then
    ok "git_subcommand_ignores_alias: $sub → $want"
  else
    fail "git_subcommand_ignores_alias ($sub): want $want got $rc"
  fi
}
ignores_is commit 0
ignores_is status 0
ignores_is whatchanged 1 # deprecated, so git still honors an alias for it
ignores_is maintenance 1 # added after 2.25, so an older git may honor one
ignores_is qc 1          # no builtin by that name at all

admit_is() {
  local desc="$1" want="$2" rc=0
  shift 2
  hook::git_alias_admit "$@" || rc=$?
  if ((rc == want)); then
    ok "git_alias_admit: $desc"
  else
    fail "git_alias_admit ($desc): want $want got $rc"
  fi
}
HOOK_ALIAS_WORK_MAX=4
HOOK_ALIAS_SEEN=()
HOOK_EFFECTIVE_BASE=/one
admit_is "a fresh state is analyzed" 0 git a
admit_is "the same state again is skipped" 1 git a
HOOK_ALIAS_SEEN=(x)
admit_is "the seen-set is part of the state" 0 git a
HOOK_ALIAS_SEEN=()
HOOK_EFFECTIVE_BASE=/two
admit_is "the effective base is part of the state" 0 git a
HOOK_EFFECTIVE_BASE=/one
admit_is "the kind tag separates a reparse string from an argv" 0 shell a
admit_is "past the ceiling the budget is reported spent" 2 git b
unset HOOK_ALIAS_WORK_MAX HOOK_ALIAS_ADMIT_ARMED HOOK_ALIAS_MEMO HOOK_ALIAS_WORK HOOK_ALIAS_SEEN
HOOK_EFFECTIVE_BASE="$gitinv_saved_base"

bs_release_fifo="$(mktemp -u)"
bs_mkfifo_err=$(mkfifo "$bs_release_fifo" 2>&1)
if [[ -z "$bs_mkfifo_err" ]] && [[ -p "$bs_release_fifo" ]]; then
  bs_hold_open() { read -r _ <"$bs_release_fifo"; }
  bs_release() { : >"$bs_release_fifo"; }
else
  printf 'WARNING: mkfifo unavailable (%s); buffer_stdin cases fall back to a fixed hold, which is slower and less precise.\n' \
    "${bs_mkfifo_err:-no FIFO created}" >&2
  bs_hold_open() { sleep 60; }
  bs_release() { :; }
fi

bs_rc_file="$(mktemp)"
bs_err_file="$(mktemp)"
{
  printf '{"incomplete":'
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.4 hook::buffer_stdin >/dev/null 2>"$bs_err_file"
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
if [[ "$bs_rc" == "2" ]] && grep -q 'BLOCKED:' "$bs_err_file"; then # portability-ok: grep -q quiet match, not grep -P
  ok "buffer_stdin: incomplete JSON past timeout → return 2 + BLOCKED on stderr"
else
  fail "buffer_stdin timeout: rc=$bs_rc err=$(cat "$bs_err_file")"
fi
rm -f "$bs_rc_file" "$bs_err_file"

bs_case() { # bs_case <label> <stdin> <want rc> <stderr has | -> <stderr lacks | ->
  local label="$1" stdin="$2" want="$3" has="$4" hasnt="$5" rc=0 err
  err=$(printf '%s' "$stdin" | hook::buffer_stdin 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" == "$want" ]] &&
    { [[ "$has" == "-" ]] || [[ "$err" == *"$has"* ]]; } &&
    { [[ "$hasnt" == "-" ]] || [[ "$err" != *"$hasnt"* ]]; }; then
    ok "buffer_stdin: $label → rc $rc"
  else
    fail "buffer_stdin: $label: rc=$rc (want $want) err=$err"
  fi
}
bs_case "truncated object at EOF is cut short" '{"tool_name":"Bash","tool_input":{"command":"ls' 3 'cut short' 'BLOCKED'
bs_case "cut-short diagnostic says the pipe closed, not stalled" '{"tool_input":{"command":' 3 'pipe closed' 'went quiet'
bs_case "truncated right after a nested close brace is still cut short" '{"tool_input":{"command":"x"}' 3 'cut short' '-'
bs_case "truncated inside a string value is cut short" '{"tool_input":{"command":"cat > f' 3 'cut short' '-'
bs_case "a lone opening brace is cut short" '{' 3 'cut short' '-'
bs_case "text that is not JSON still fails closed" 'not json' 2 'not valid JSON' 'cut short'
bs_case "a complete document plus trailing junk is not JSON" '{"a":1} x' 2 'not valid JSON' 'cut short'
bs_case "structurally wrong JSON is not JSON" '{"a" 1}' 2 'not valid JSON' 'cut short'
bs_case "an over-closed document is not JSON" '{"a":1}}' 2 'not valid JSON' 'cut short'
bs_case "whitespace-only stdin is empty" $' \n' 1 '-' 'cut short'
bs_case "a complete payload still parses" '{"tool_input":{"command":"ls"}}' 0 '-' '-'
bs_rc_file="$(mktemp)"
bs_err_file="$(mktemp)"
{
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls'
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.4 hook::buffer_stdin >/dev/null 2>"$bs_err_file"
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
# portability-ok: grep -q quiet match, not grep -P
if [[ "$bs_rc" == "2" ]] && grep -q 'BLOCKED: hook stdin timed out before a complete JSON payload arrived' "$bs_err_file" && ! grep -q 'cut short' "$bs_err_file"; then
  ok "buffer_stdin: the truncated-object prefix with the pipe held open past the bound → rc 2 timed out (a stall is not cut short)"
else
  fail "buffer_stdin stall-vs-EOF discriminator: rc=$bs_rc (want 2) err=$(cat "$bs_err_file")"
fi
rm -f "$bs_rc_file" "$bs_err_file"
bs_rc_file="$(mktemp)"
bs_err_file="$(mktemp)"
{
  printf ' \n'
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.4 hook::buffer_stdin >/dev/null 2>"$bs_err_file"
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
# portability-ok: grep -q quiet match, not grep -P
if [[ "$bs_rc" == "2" ]] && grep -q 'BLOCKED: hook stdin timed out before a complete JSON payload arrived' "$bs_err_file"; then
  ok "buffer_stdin: whitespace-only stdin with the pipe held open past the bound → rc 2 timed out (a stall is decided before the empty-payload check)"
else
  fail "buffer_stdin whitespace-only stall: rc=$bs_rc (want 2) err=$(cat "$bs_err_file")"
fi
rm -f "$bs_rc_file" "$bs_err_file"
bs_jq_err=$(printf '{"a":' | jq -e . 2>&1 >/dev/null) || true # jq exits 5 here by design; the wording is the subject
if [[ "$bs_jq_err" == *Unfinished* ]]; then
  ok "jq names a document that ended early 'Unfinished' (the cut-short oracle holds on this jq)"
else
  fail "jq no longer says 'Unfinished' for a truncated document: $bs_jq_err"
fi

bs_rc_file="$(mktemp)"
bs_out_file="$(mktemp)"
{
  printf '{"complete":true}'
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.4 hook::buffer_stdin >"$bs_out_file" 2>/dev/null
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
if [[ "$bs_rc" == "0" ]] && [[ "$(cat "$bs_out_file")" == '{"complete":true}' ]]; then
  ok "buffer_stdin: complete JSON on a pipe held open past timeout → rc 0 + payload"
else
  fail "buffer_stdin late-EOF: rc=$bs_rc out=$(cat "$bs_out_file")"
fi

rm -f "$bs_rc_file" "$bs_out_file"

bs_big_file="$(mktemp)"
bs_payload_file="$(mktemp)"
bs_rc_file="$(mktemp)"
bs_out_file="$(mktemp)"
yes 'portable content with no delimiters of interest' | head -c 262144 >"$bs_big_file"
jq -cn --rawfile c "$bs_big_file" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:"/tmp/big.md",content:$c}}' \
  >"$bs_payload_file"
# shellcheck disable=SC2002 # `cat |` is the point: it forces a real pipe on fd 0.
cat "$bs_payload_file" | {
  hook::buffer_stdin >"$bs_out_file" 2>/dev/null
  echo "$?" >"$bs_rc_file"
}
bs_rc=$(cat "$bs_rc_file")
bs_len=$(wc -c <"$bs_out_file")
bs_content_len=$(jq -r '.tool_input.content | length' "$bs_out_file" 2>/dev/null || echo 0)
if [[ "$bs_rc" == "0" ]] && ((bs_content_len == 262144)); then
  ok "buffer_stdin: 256 KB payload on a pipe → rc 0, payload intact ($bs_len bytes)"
else
  fail "buffer_stdin large payload: rc=$bs_rc content_len=$bs_content_len buffered=$bs_len bytes"
fi
rm -f "$bs_big_file" "$bs_payload_file" "$bs_rc_file" "$bs_out_file"

bs_tick_fifo="$(mktemp -u)"
# shellcheck disable=SC2034 # `bs_tick_discard` is the read target; only stderr matters
bs_tick_probe=$(read -r -t 0.1 bs_tick_discard </dev/null 2>&1)
if [[ -z "$bs_tick_probe" ]] && mkfifo "$bs_tick_fifo" 2>/dev/null &&
  exec 9<>"$bs_tick_fifo"; then
  bs_tick_kind="fifo"
  bs_tick() { read -r -t "$1" -u 9 _; }
else
  bs_tick_kind="sleep spawn"
  bs_tick() { sleep "$1"; }
fi
bs_tick_t0=${EPOCHREALTIME:-}
for _ in 1 2 3 4 5; do bs_tick 0.1; done
bs_tick_t1=${EPOCHREALTIME:-}
if [[ -z "$bs_tick_t0" || -z "$bs_tick_t1" ]]; then
  ok "trickle tick ($bs_tick_kind): delay not timed (EPOCHREALTIME absent, Bash < 5.0)"
else
  bs_tick_ms=$(awk -v s="$bs_tick_t0" -v e="$bs_tick_t1" 'BEGIN { printf "%.0f", (e - s) * 1000 }')
  if ((bs_tick_ms >= 400)); then
    ok "trickle tick ($bs_tick_kind): 5 x 0.1 s really delays (${bs_tick_ms} ms)"
  else
    fail "trickle tick ($bs_tick_kind): 5 x 0.1 s took only ${bs_tick_ms} ms — the tick does not delay, so the trickle case below is vacuous"
  fi
fi
bs_rc_file="$(mktemp)"
bs_out_file="$(mktemp)"
{
  printf '{"a":"'
  for ((bs_i = 0; bs_i < 20; bs_i++)); do
    bs_tick 0.1
    printf 'x'
  done
  printf '"}'
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1.2 hook::buffer_stdin >"$bs_out_file" 2>/dev/null
  echo "$?" >"$bs_rc_file"
}
bs_rc=$(cat "$bs_rc_file")
if [[ "$bs_rc" == "0" ]] && [[ "$(cat "$bs_out_file")" == '{"a":"xxxxxxxxxxxxxxxxxxxx"}' ]]; then
  ok "buffer_stdin: steady trickle slower than one chunk per window → rc 0 (idle bound)"
else
  fail "buffer_stdin trickle: rc=$bs_rc out=$(cat "$bs_out_file")"
fi

: >"$bs_out_file"
{
  printf '{"a":"'
  for _ in 1 2 3 4 5; do
    bs_tick 0.1
    printf 'x'
  done
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.3 hook::buffer_stdin >"$bs_out_file" 2>/dev/null
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
if [[ "$bs_rc" == "2" ]]; then
  ok "buffer_stdin: trickle that then goes silent mid-payload → still rc 2"
else
  fail "buffer_stdin trickle-then-stall: rc=$bs_rc out=$(cat "$bs_out_file")"
fi
rm -f "$bs_rc_file" "$bs_out_file"
[[ "$bs_tick_kind" == fifo ]] && exec 9<&-
rm -f "$bs_tick_fifo"

bs_big_file="$(mktemp)"
bs_payload_file="$(mktemp)"
bs_rc_file="$(mktemp)"
bs_out_file="$(mktemp)"
# shellcheck disable=SC2016 # $1 is deliberately the CHILD shell's positional, not this one's
force_legacy='source "$1"; hook::read_supports_nchars() { return 1; }; '

bs_branch=$(bash -c "${force_legacy}"'hook::read_supports_nchars && echo modern || echo legacy' \
  _ "$HOOK_DIR/hook-utils.sh")
if [[ "$bs_branch" == "legacy" ]]; then
  ok "buffer_stdin: pre-4.1 guard override selects the delimiter-read branch"
else
  fail "pre-4.1 override did not flip the branch (got '$bs_branch'); cases below are vacuous"
fi

yes 'portable content with no delimiters of interest' | head -c 131072 >"$bs_big_file"
jq -cn --rawfile c "$bs_big_file" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:"/tmp/big.md",content:$c}}' \
  >"$bs_payload_file"
# shellcheck disable=SC2002 # `cat |` is the point: it forces a real pipe on fd 0.
cat "$bs_payload_file" | {
  bash -c "${force_legacy}"'hook::buffer_stdin' _ "$HOOK_DIR/hook-utils.sh" \
    >"$bs_out_file" 2>/dev/null
  echo "$?" >"$bs_rc_file"
}
bs_rc=$(cat "$bs_rc_file")
bs_content_len=$(jq -r '.tool_input.content | length' "$bs_out_file" 2>/dev/null || echo 0)
if [[ "$bs_rc" == "0" ]] && ((bs_content_len == 131072)); then
  ok "buffer_stdin: pre-4.1 delimiter-read fallback buffers a 128 KB payload (rc 0)"
else
  fail "buffer_stdin pre-4.1 fallback: rc=$bs_rc content_len=$bs_content_len"
fi

: >"$bs_out_file"
{
  printf '{"incomplete":'
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.4 \
    bash -c "${force_legacy}"'hook::buffer_stdin' _ "$HOOK_DIR/hook-utils.sh" \
    >"$bs_out_file" 2>/dev/null
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
if [[ "$bs_rc" == "2" ]]; then
  ok "buffer_stdin: pre-4.1 fallback still fails closed on a stalled pipe (rc 2)"
else
  fail "buffer_stdin pre-4.1 stall: rc=$bs_rc"
fi
rm -f "$bs_big_file" "$bs_payload_file" "$bs_rc_file" "$bs_out_file"

for bs_bad in "abc" "0" "-1" "1e3" ""; do
  bs_rc_file="$(mktemp)"
  bs_out_file="$(mktemp)"
  bs_err_file="$(mktemp)"
  printf '{"ok":true}' | {
    CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT="$bs_bad" hook::buffer_stdin \
      >"$bs_out_file" 2>"$bs_err_file"
    echo "$?" >"$bs_rc_file"
  }
  bs_rc=$(cat "$bs_rc_file")
  if [[ "$bs_rc" == "0" ]] && [[ "$(cat "$bs_out_file")" == '{"ok":true}' ]] &&
    [[ ! -s "$bs_err_file" ]]; then
    ok "buffer_stdin: unusable stdin_read_timeout '$bs_bad' → default, payload intact, no stderr"
  else
    fail "buffer_stdin bad timeout '$bs_bad': rc=$bs_rc out=$(cat "$bs_out_file") err=$(cat "$bs_err_file")"
  fi
  rm -f "$bs_rc_file" "$bs_out_file" "$bs_err_file"
done

for bs_submin in "0.0000001" "0.000001"; do
  bs_rc_file="$(mktemp)"
  bs_out_file="$(mktemp)"
  bs_err_file="$(mktemp)"
  printf '{"ok":true}' | {
    CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT="$bs_submin" hook::buffer_stdin \
      >"$bs_out_file" 2>"$bs_err_file"
    echo "$?" >"$bs_rc_file"
  }
  bs_rc=$(cat "$bs_rc_file")
  if [[ "$bs_rc" == "0" ]] && [[ "$(cat "$bs_out_file")" == '{"ok":true}' ]] &&
    [[ ! -s "$bs_err_file" ]]; then
    ok "buffer_stdin: sub-minimum stdin_read_timeout '$bs_submin' → default"
  else
    fail "buffer_stdin sub-minimum timeout '$bs_submin': rc=$bs_rc"
  fi
  rm -f "$bs_rc_file" "$bs_out_file" "$bs_err_file"
done
resolve_timeout_under() { # <option-value>
  (
    CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT="$1"
    local __t=""
    hook::resolve_read_timeout_to __t
    printf '%s' "$__t"
  )
}
resolved=$(resolve_timeout_under 0.00001)
if [[ "$resolved" == "0.00001" ]]; then
  ok "resolve_read_timeout_to: floor value 0.00001 is honored"
else
  fail "resolve_read_timeout_to floor: got '$resolved' (expected 0.00001)"
fi
resolved=$(resolve_timeout_under 0.0000001)
if [[ "$resolved" == "2" ]]; then
  ok "resolve_read_timeout_to: below-floor value degrades to default"
else
  fail "resolve_read_timeout_to below floor: got '$resolved' (expected 2)"
fi

# shellcheck disable=SC2016 # $1 is the child shell's positional, not this one's
force_no_frac='source "$1"; hook::read_supports_fractional_timeout() { return 1; }; '
frac_branch=$(bash -c "${force_no_frac}"'hook::read_supports_fractional_timeout && echo modern || echo legacy' \
  _ "$HOOK_DIR/hook-utils.sh")
if [[ "$frac_branch" == "legacy" ]]; then
  ok "read_supports_fractional_timeout: override selects the Bash 3.2 branch"
else
  fail "fractional-timeout override did not flip the branch (got '$frac_branch')"
fi
# shellcheck disable=SC2016 # the dest vars are the child shell's, not this one's
print_slice='s=""; c=""; hook::resolve_read_slice_to "$2" s c; printf "%s %s" "$s" "$c"'
# shellcheck disable=SC2016 # the dest var is the child shell's, not this one's
print_timeout='t=""; hook::resolve_read_timeout_to t; printf "%s" "$t"'
frac_slice=$(bash -c "${force_no_frac}${print_slice}" _ "$HOOK_DIR/hook-utils.sh" 2)
if [[ "$frac_slice" == "2 1" ]]; then
  ok "resolve_read_slice_to: Bash 3.2 fallback is unsliced '<timeout> 1'"
else
  fail "resolve_read_slice_to 3.2 fallback: got '$frac_slice' (expected '2 1')"
fi
frac_t=$(CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.5 bash -c "${force_no_frac}${print_timeout}" \
  _ "$HOOK_DIR/hook-utils.sh")
if [[ "$frac_t" == "2" ]]; then
  ok "resolve_read_timeout_to: fractional custom value degrades to default on Bash 3.2"
else
  fail "resolve_read_timeout_to 3.2 fractional: got '$frac_t' (expected 2)"
fi
frac_int=$(CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=5 bash -c "${force_no_frac}${print_timeout}" \
  _ "$HOOK_DIR/hook-utils.sh")
if [[ "$frac_int" == "5" ]]; then
  ok "resolve_read_timeout_to: integer custom value is honored on Bash 3.2"
else
  fail "resolve_read_timeout_to 3.2 integer: got '$frac_int' (expected 5)"
fi

bs_rc_file="$(mktemp)"
{
  printf '{"incomplete":'
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.5 hook::buffer_stdin >/dev/null 2>&1
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
if [[ "$bs_rc" == "2" ]]; then
  ok "buffer_stdin: a valid non-default stdin_read_timeout is honored, not overridden"
else
  fail "buffer_stdin valid non-default timeout: rc=$bs_rc (expected 2)"
fi
rm -f "$bs_rc_file"

bs_time_stall() { # $1 = shell prelude; prints elapsed ms (empty if untimed)
  local t_file
  t_file="$(mktemp)"
  {
    printf '{"partial":'
    bs_hold_open
  } | {
    CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=3.6 bash -c '
      source "$1"
      eval "$2"
      printf "%s\n" "${EPOCHREALTIME:-0}"
      hook::buffer_stdin >/dev/null 2>&1
      printf "%s\n" "${EPOCHREALTIME:-0}"
    ' _ "$HOOK_DIR/hook-utils.sh" "$1" >"$t_file"
    bs_release
  }
  awk 'NR==1 {s=$0} NR==2 {e=$0}
       END { if (s == 0 || e == 0 || NR < 2) print ""; else printf "%.0f", (e - s) * 1000 }' \
    "$t_file"
  rm -f "$t_file"
}
# shellcheck disable=SC2016 # $1 is the overriding function's own positional, not this shell's
bs_unsliced='hook::resolve_read_slice_to() {
  printf -v "$2" "%s" "$1"
  printf -v "$3" "%s" "1"
}'
bs_slices=$(bash -c "source \"\$1\"; ${print_slice}" _ "$HOOK_DIR/hook-utils.sh" 3.6)
bs_slices_forced=$(bash -c "source \"\$1\"; ${bs_unsliced}; ${print_slice}" \
  _ "$HOOK_DIR/hook-utils.sh" 3.6)
if [[ "$bs_slices" == "0.900 4" ]] && [[ "$bs_slices_forced" == "3.6 1" ]]; then
  ok "buffer_stdin: slice resolution splits the bound, and the unsliced override engages"
else
  fail "slice resolution: got '$bs_slices' / forced '$bs_slices_forced'; cases below are vacuous"
fi
bs_make_payload() { # $1 = exact payload length in bytes, $2 = destination file
  local pad
  printf -v pad '%*s' "$(($1 - 8))" ''
  printf '{"p":"%s"}' "${pad// /a}" >"$2"
}
bs_len_file="$(mktemp)"
bs_make_payload 65536 "$bs_len_file"
bs_len_a=$(wc -c <"$bs_len_file")
bs_make_payload 65000 "$bs_len_file"
bs_len_b=$(wc -c <"$bs_len_file")
rm -f "$bs_len_file"
if ((bs_len_a == 65536)) && ((bs_len_b == 65000)); then
  ok "buffer_stdin: chunk-boundary fixtures are exactly sized ($bs_len_a / $bs_len_b)"
else
  fail "chunk-boundary fixtures wrong size ($bs_len_a / $bs_len_b); the case below is vacuous"
fi
bs_payload_file="$(mktemp)"
bs_rc_file="$(mktemp)"
bs_out_file="$(mktemp)"
bs_make_payload 65536 "$bs_payload_file"
bs_payload=$(<"$bs_payload_file")
{
  printf '%s' "$bs_payload"
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1.2 hook::buffer_stdin >"$bs_out_file" 2>/dev/null
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
bs_len=$(wc -c <"$bs_out_file")
if [[ "$bs_rc" == "0" ]] && ((bs_len == 65536 && ${#bs_payload} == 65536)); then
  ok "buffer_stdin: an exactly-chunk-sized payload on a held-open pipe returns whole (rc 0, $bs_len bytes)"
else
  fail "buffer_stdin chunk boundary: rc=$bs_rc len=$bs_len payload=${#bs_payload} (expected rc 0, 65536 bytes)"
fi
rm -f "$bs_payload_file" "$bs_rc_file" "$bs_out_file"

bs_probe_file="$(mktemp)"
bs_payload_file="$(mktemp)"
bs_rc_file="$(mktemp)"
bs_out_file="$(mktemp)"
bs_make_payload 65536 "$bs_payload_file"
bs_payload=$(<"$bs_payload_file")
# shellcheck disable=SC2016 # $1 is the overriding function's own positional, not this shell's
bs_probe_override='hook::json_complete() {
  local verdict=0
  printf "%s" "$1" | jq -e . >/dev/null 2>&1 || verdict=$?
  if ((verdict == 0)); then
    printf "idle=%s chunklen=%s\n" "${__hu_idle_slices-?}" "${#__hu_chunk}" >>"'"$bs_probe_file"'"
  fi
  return "$verdict"
}'
bs_probe_run() { # sets bs_rc, bs_len, bs_probe_last from one whole-payload run
  : >"$bs_probe_file"
  {
    printf '%s' "$bs_payload" # builtin: the first byte must not wait on a spawn
    bs_hold_open
  } | {
    CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1.2 bash -c '
      source "$1"
      eval "$2"
      hook::buffer_stdin >"$3" 2>/dev/null
      printf "%s" "$?" >"$4"
    ' _ "$HOOK_DIR/hook-utils.sh" "$bs_probe_override" "$bs_out_file" "$bs_rc_file"
    bs_release
  }
  bs_rc=$(cat "$bs_rc_file")
  bs_len=$(wc -c <"$bs_out_file")
  bs_probe_last=$(tail -n 1 "$bs_probe_file")
}
bs_engagement=""
for bs_attempt in 1 2 3; do
  bs_probe_run
  if [[ "$bs_rc" == "0" ]] && ((bs_len == 65536 && ${#bs_payload} == 65536)) && [[ "$bs_probe_last" == "idle=0 chunklen=0" ]]; then
    bs_engagement=exercised
    break
  fi
  if [[ "$bs_rc" == "0" ]] && ((bs_len == 65536 && ${#bs_payload} == 65536)) && [[ "$bs_probe_last" == idle=0\ chunklen=* ]]; then
    bs_engagement=fragmented # tells us nothing either way; try again
    continue
  fi
  bs_engagement=bad
  break
done
case "$bs_engagement" in
exercised)
  ok "buffer_stdin: the empty-slice completeness check fires on the FIRST idle slice for a chunk-boundary payload ($bs_probe_last, attempt $bs_attempt)"
  ;;
fragmented)
  ok "buffer_stdin: chunk-boundary payload arrived fragmented on all 3 attempts (last: $bs_probe_last), so the empty-slice check was not exercised this run — correctness holds, engagement unasserted"
  ;;
*)
  fail "buffer_stdin chunk-boundary engagement: attempt $bs_attempt gave rc=$bs_rc len=$bs_len payload=${#bs_payload} probe='$(tr '\n' ';' <"$bs_probe_file")' (expected rc 0, 65536 bytes, and a completeness verdict at idle=0 chunklen=0)"
  ;;
esac
rm -f "$bs_probe_file" "$bs_payload_file" "$bs_rc_file" "$bs_out_file"

bs_stall_read_file="$(mktemp)"
# shellcheck disable=SC2016 # read() shadows the builtin inside the stall subshell
bs_stall_read_override='read() {
  printf "x\n" >>"'"$bs_stall_read_file"'"
  builtin read "$@"
}'
: >"$bs_stall_read_file"
bs_time_stall "$bs_stall_read_override" >/dev/null
bs_sliced_reads=$(wc -l <"$bs_stall_read_file" | tr -d ' ')
: >"$bs_stall_read_file"
bs_time_stall "$bs_unsliced; $bs_stall_read_override" >/dev/null
bs_unsliced_reads=$(wc -l <"$bs_stall_read_file" | tr -d ' ')
if ((bs_sliced_reads > bs_unsliced_reads)); then
  ok "buffer_stdin: sliced stall path issues more reads than unsliced ($bs_sliced_reads vs $bs_unsliced_reads)"
else
  fail "buffer_stdin stall read engagement: sliced=$bs_sliced_reads unsliced=$bs_unsliced_reads (expected sliced > unsliced)"
fi
rm -f "$bs_stall_read_file"

rm -f "$bs_release_fifo"

tel19="$(mktemp)"
: >"$tel19"
sink19="$(make_sink "cat >\"$tel19\"")"
rc19=$(
  unset EPOCHREALTIME
  start=${EPOCHREALTIME:-}
  HOOK_TELEMETRY_SINK="$sink19" hook::emit_telemetry "t" "PostToolUse" "ok" "$start" '{"tool":"x","file":"y","findings":[]}'
  echo $?
)
sleep 0.1 # allow any (erroneous) background dispatch to land before asserting empty
if [[ "$rc19" == "0" && ! -s "$tel19" ]]; then
  ok "emit_telemetry: EPOCHREALTIME-absent (empty start) → skip fail-open (rc 0, no envelope)"
else
  fail "emit_telemetry EPOCHREALTIME-absent: rc=$rc19 sink=[$(cat "$tel19")]"
fi
rm -f "$tel19" "$sink19"

tel19b="$(mktemp)"
sink19b="$(make_sink "cat >\"$tel19b\"")"
driver19b="$(mktemp)"
blob19b="$(mktemp)"
printf 'x%.0s' {1..35000} >"$blob19b"
cat >"$driver19b" <<DRIVER
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
data_json=\$(jq -cn --rawfile blob "$blob19b" \
  '{tool:"Write",file:"src/big.py",findings:[\$blob]}')
HOOK_TELEMETRY_SINK="$sink19b" hook::emit_telemetry \
  "sample-hook" "PostToolUse" "ok" "\$EPOCHREALTIME" "\$data_json" 2>/dev/null
DRIVER
bash "$driver19b"
wait_for_sink "$tel19b" "$SINK_POLLS"
unset HOOK_TELEMETRY_SINK
if [[ -s "$tel19b" ]]; then
  blob_len=$(jq -r '.data.findings[0] | length' "$tel19b" 2>/dev/null || echo 0)
  if ((blob_len == 35000)); then
    ok "emit_telemetry: 35 KB data_json payload → sink intact ($blob_len bytes)"
  else
    fail "emit_telemetry large payload: findings len=$blob_len (want 35000)"
  fi
else
  fail "emit_telemetry large payload: sink empty (telemetry dropped)"
fi
rm -f "$tel19b" "$sink19b" "$driver19b" "$blob19b"

subject_is() {
  local desc="$1" tool="$2" cmd="$3" want="$4" got
  got=$(hook::extract_bash_subject "$tool" "$cmd")
  if [[ "$got" == "$want" ]]; then
    ok "extract_bash_subject: $desc"
  else
    fail "extract_bash_subject ($desc): want [$want] got [$got]"
  fi
}

subject_is "bare trailing assignment bails to Bash" \
  "Bash" "TOKEN=ghp_realtokenvalue" "Bash"
subject_is "path-valued trailing assignment bails (no basename leak)" \
  "Bash" "TOKEN=/a/b/secret" "Bash"
subject_is "trailing multi-assignment bails to Bash" \
  "Bash" "VAR=x TOKEN=secret" "Bash"
subject_is "trailing append assignment bails to Bash" \
  "Bash" "TOKEN+=ghp_secret" "Bash"
subject_is "trailing subscripted assignment bails to Bash" \
  "Bash" "TOKEN[0]=ghp_secret" "Bash"
subject_is "trailing subscripted append assignment bails to Bash" \
  "Bash" "TOKEN[0]+=ghp_secret" "Bash"
subject_is "trailing nested-subscript assignment bails to Bash" \
  "Bash" "TOKEN[1+INDEX[0]]=ghp_secret" "Bash"

subject_is "leading assignment prefix then a command yields the command" \
  "Bash" "VAR=x realcmd --flag arg" "Bash:realcmd"
subject_is "quoted assignment value bails to Bash" \
  "Bash" 'TOKEN="a b" curl https://x' "Bash"
subject_is "ordinary command yields basename subject" \
  "Bash" "/usr/bin/git status --short" "Bash:git"
subject_is "non-Bash tool returns the tool name" \
  "Write" "irrelevant" "Write"

resolve_dirs_are() {
  local desc="$1" expected="$2"
  shift 2
  local got rc
  hook::git_resolve_index "$@"
  rc=$?
  got=$(
    IFS='|'
    printf '%s' "${HOOK_GIT_RESOLVED_WRAPPER_DIRS[*]-}"
  )
  if ((rc != 0)); then
    fail "$desc: resolver did not find git (rc=$rc)"
  elif [[ "$got" == "$expected" ]]; then
    ok "$desc"
  else
    fail "$desc: expected [$expected], got [$got]"
  fi
}

resolve_dirs_are "no wrapper reports no chdir" "" git commit
resolve_dirs_are "env with no options reports no chdir" "" env git commit
resolve_dirs_are "env -C DIR reports the chdir" "other" env -C other git commit
resolve_dirs_are "env -CDIR (attached short) reports the chdir" "other" env -Cother git commit
resolve_dirs_are "env --chdir DIR reports the chdir" "other" env --chdir other git commit
resolve_dirs_are "env --chdir=DIR reports the chdir" "other" env --chdir=other git commit
resolve_dirs_are "env -vC DIR (clustered) reports the chdir" "other" env -vC other git commit
resolve_dirs_are "env -iC DIR (clustered) reports the chdir" "other" env -iC other git commit
resolve_dirs_are "env -u swallows -C, so no chdir is reported" "" env -u -C git commit
resolve_dirs_are "env -uNAME (attached) leaves a later -C as env's chdir" "other" env -uFOO -C other git commit
resolve_dirs_are "repeated env -C is last-wins within one env" "second" env -C first -C second git commit
resolve_dirs_are "env NAME=value operand carries no chdir" "" env FOO=bar git commit
resolve_dirs_are "env -- ends option parsing" "other" env -C other -- git commit
resolve_dirs_are "a chdir BEFORE the operand still counts" "other" env -C other FOO=1 git commit
if hook::git_resolve_index env FOO=1 -C other git commit; then
  fail "a NAME=value operand ends option parsing: resolved git at $HOOK_GIT_RESOLVED_GI, expected none"
else
  ok "a NAME=value operand ends option parsing, so no git resolves"
fi
resolve_dirs_are "sudo -D DIR reports the chdir" "other" sudo -D other git commit
resolve_dirs_are "sudo --chdir=DIR reports the chdir" "other" sudo --chdir=other git commit
resolve_dirs_are "sudo -C fd is not a chdir" "" sudo -C 3 git commit
resolve_dirs_are "sudo -bD DIR peels the valueless short and reports the chdir" "other" sudo -bDother git commit
resolve_dirs_are "sudo -nD DIR peels -n and reports the chdir" "other" sudo -nDother git commit
resolve_dirs_are "sudo -AD DIR peels -A and reports the chdir" "other" sudo -ADother git commit
resolve_dirs_are "sudo -hD DIR does not peel -h and does not treat git as chdir" "" sudo -hD git commit
resolve_dirs_are "nested wrappers report both chdirs in order" "a|b" env -C a sudo -D b git commit
resolve_dirs_are "env -S splices a chdir that belongs to env" "other" env -S '-C other git commit'
resolve_dirs_are "env --split-string= splices a chdir that belongs to env" "other" env --split-string='-C other git commit'
resolve_dirs_are "env -S with an attached operand splices the chdir" "other" env "-S-C other git commit"
resolve_dirs_are "env -S with no leading option still resolves git" "" env -S 'git commit'
resolve_dirs_are "env -C first -S '-C second …' is last-wins in the one slot" "second" env -C first -S '-C second git commit'
resolve_dirs_are "env -S '-v -C DIR git …' keeps the chdir" "other" env -S '-v -C other git commit'
if hook::git_resolve_index env -S '-S -S'; then
  fail "env -S '-S -S' should resolve no git, resolved at $HOOK_GIT_RESOLVED_GI"
else
  ok "a self-referential env -S terminates and resolves no git"
fi

slice_is() {
  local label="$1" input="$2" want="$3" slice="" count="" got
  hook::resolve_read_slice_to "$input" slice count
  got="$slice $count"
  if [[ "$got" == "$want" ]]; then
    ok "resolve_read_slice_to: $label"
  else
    fail "resolve_read_slice_to $label: got '$got', want '$want'"
  fi
}
slice_is "the default bound splits into four 500 ms slices" 2 "0.500 4"
slice_is "an integer bound divides exactly" 10 "2.500 4"
slice_is "a fractional bound keeps three decimals" 0.5 "0.125 4"
slice_is "a sub-slice bound still yields a usable slice" 0.004 "0.001 4"
slice_is "a zero bound falls back to the unsliced form" 0.000 "0.000 1"
slice_is "a non-numeric bound falls back to the unsliced form" abc "abc 1"

jf_input='{"tool_name":"Bash","tool_input":{"command":"git status\nsecond line\r"},"session_id":"s-1"}'

if hook::jq_fields "$jf_input" '.tool_input.command' '.tool_name' '.session_id'; then
  if [[ "${#HOOK_JQ_FIELDS[@]}" -eq 3 &&
    "${HOOK_JQ_FIELDS[0]}" == $'git status\nsecond line' &&
    "${HOOK_JQ_FIELDS[1]}" == "Bash" &&
    "${HOOK_JQ_FIELDS[2]}" == "s-1" ]]; then
    ok "jq_fields: multi-line, CR-carrying values survive the NUL-separated read"
  else
    fail "jq_fields values: got (${#HOOK_JQ_FIELDS[@]}) '${HOOK_JQ_FIELDS[0]-}' / '${HOOK_JQ_FIELDS[1]-}' / '${HOOK_JQ_FIELDS[2]-}'"
  fi
else
  fail "jq_fields returned $? on a well-formed payload"
fi

if hook::jq_fields "$jf_input" '.tool_input.file_path' '.tool_name'; then
  if [[ "${#HOOK_JQ_FIELDS[@]}" -eq 2 && -z "${HOOK_JQ_FIELDS[0]}" && "${HOOK_JQ_FIELDS[1]}" == "Bash" ]]; then
    ok "jq_fields: an absent field keeps its slot instead of shifting the rest"
  else
    fail "jq_fields absent-field slot: got (${#HOOK_JQ_FIELDS[@]}) '${HOOK_JQ_FIELDS[0]-}' / '${HOOK_JQ_FIELDS[1]-}'"
  fi
else
  fail "jq_fields returned $? when a requested field was absent"
fi

hook::jq_fields 'not json at all' '.tool_name' '.session_id'
rc=$?
if ((rc == 2 && ${#HOOK_JQ_FIELDS[@]} == 0)); then
  ok "jq_fields: an unparsable payload returns 2 and leaves no values"
elif ((rc == 0)); then
  fail "jq_fields accepted an unparsable payload"
else
  fail "jq_fields left ${#HOOK_JQ_FIELDS[@]} values after an unparsable payload (rc=$rc)"
fi

if hook::jq_fields "$jf_input"; then
  fail "jq_fields accepted a call with no filters"
else
  ok "jq_fields: a call with no filters returns non-zero"
fi

jf_nul_input=$(jq -nc '{tool_name:"Write",tool_input:{content:("before" + ([0] | implode) + "after")}}')
jf_nul_input="${jf_nul_input//$'\r'/}"
if hook::jq_fields "$jf_nul_input" '.tool_name' '.tool_input.content'; then
  if [[ "${#HOOK_JQ_FIELDS[@]}" -eq 2 &&
    "${HOOK_JQ_FIELDS[0]}" == "Write" &&
    "${HOOK_JQ_FIELDS[1]}" == "beforeafter" ]]; then
    ok "jq_fields: a NUL inside a value is stripped, never read as the delimiter"
  else
    fail "jq_fields NUL-bearing value: got (${#HOOK_JQ_FIELDS[@]}) '${HOOK_JQ_FIELDS[0]-}' / '${HOOK_JQ_FIELDS[1]-}'"
  fi
else
  fail "jq_fields returned $? on a NUL-bearing value — the caller's || exit 0 would skip its guard"
fi

if hook::jq_fields '{"a":5,"b":null}' '.a' '.b' &&
  [[ "${HOOK_JQ_FIELDS[0]}" == "5" && -z "${HOOK_JQ_FIELDS[1]}" ]]; then
  ok "jq_fields: a number stringifies and a null becomes the empty string"
else
  fail "jq_fields non-string handling: got '${HOOK_JQ_FIELDS[0]-}' / '${HOOK_JQ_FIELDS[1]-}'"
fi

jf_bs=$(jq -rn '[92] | implode')
jf_nul=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: ("git push --no-veri" + ([0] | implode) + "fy") },
  session_id: ("s" + ([0] | implode) + "1"),
  only_nul: ([0] | implode),
  runs: ("p" + ([0] | implode) + ([0] | implode) + "q"),
  literal: (([92] | implode) + "u0000")
}')

if hook::jq_fields "$jf_nul" \
  '.tool_input.command' '.tool_name' '.session_id' '.only_nul' '.runs' '.literal' '.absent'; then
  if [[ "${#HOOK_JQ_FIELDS[@]}" -eq 7 &&
    "${HOOK_JQ_FIELDS[0]}" == "git push --no-verify" &&
    "${HOOK_JQ_FIELDS[1]}" == "Bash" &&
    "${HOOK_JQ_FIELDS[2]}" == "s1" &&
    -z "${HOOK_JQ_FIELDS[3]}" &&
    "${HOOK_JQ_FIELDS[4]}" == "pq" &&
    "${HOOK_JQ_FIELDS[5]}" == "${jf_bs}u0000" &&
    -z "${HOOK_JQ_FIELDS[6]}" ]]; then
    ok "jq_fields: a NUL-bearing value keeps every slot and is stripped, not split"
  else
    fail "jq_fields NUL framing: got (${#HOOK_JQ_FIELDS[@]}) '${HOOK_JQ_FIELDS[0]-}' / '${HOOK_JQ_FIELDS[1]-}' / '${HOOK_JQ_FIELDS[2]-}' / '${HOOK_JQ_FIELDS[3]-}' / '${HOOK_JQ_FIELDS[4]-}' / '${HOOK_JQ_FIELDS[5]-}' / '${HOOK_JQ_FIELDS[6]-}'"
  fi
else
  fail "jq_fields returned $? on a payload whose value carried a NUL"
fi

if hook::jq_fields "$jf_nul" '.tool_input.command'; then
  if [[ "$HOOK_JQ_FIELDS_NUL" == 1 ]]; then
    ok "jq_fields: a NUL is reported to the caller instead of returning its fail-open code"
  else
    fail "jq_fields HOOK_JQ_FIELDS_NUL: expected 1 on a NUL-bearing payload, got '$HOOK_JQ_FIELDS_NUL'"
  fi
else
  fail "jq_fields returned $? on a NUL-bearing payload — callers spell that ALLOW"
fi

if hook::jq_fields "$jf_nul" '.tool_name' '.only_nul' && [[ "$HOOK_JQ_FIELDS_NUL" == 1 ]]; then
  ok "jq_fields: a NUL in any requested field raises the flag"
else
  fail "jq_fields flag on a trailing NUL field: got '$HOOK_JQ_FIELDS_NUL'"
fi

jf_lead=$(jq -n '{tool_input: {command: (([0] | implode) + "git push --force")}}')
if hook::jq_fields "$jf_lead" '.tool_input.command' &&
  [[ "${HOOK_JQ_FIELDS[0]}" == "git push --force" && "$HOOK_JQ_FIELDS_NUL" == 1 ]]; then
  ok "jq_fields: a leading NUL keeps the value's text and still raises the flag"
else
  fail "jq_fields leading NUL: got '${HOOK_JQ_FIELDS[0]-}' flag '$HOOK_JQ_FIELDS_NUL'"
fi

jf_splice=$(jq -n '{tool_input: {command: ("git commit --no-verify" + ([0] | implode) + "x")}}')
if hook::jq_fields "$jf_splice" '.tool_input.command' &&
  [[ "${HOOK_JQ_FIELDS[0]}" == "git commit --no-verifyx" && "$HOOK_JQ_FIELDS_NUL" == 1 ]]; then
  ok "jq_fields: stripping splices a token the payload never carried, and flags it"
else
  fail "jq_fields splice: got '${HOOK_JQ_FIELDS[0]-}' flag '$HOOK_JQ_FIELDS_NUL'"
fi

jf_allnul=$(jq -n '{tool_input: {command: (([0] | implode) + ([0] | implode))}}')
if hook::jq_fields "$jf_allnul" '.tool_input.command' &&
  [[ -z "${HOOK_JQ_FIELDS[0]}" && "$HOOK_JQ_FIELDS_NUL" == 1 ]]; then
  ok "jq_fields: an all-NUL value strips to empty and still raises the flag"
else
  fail "jq_fields all-NUL: got '${HOOK_JQ_FIELDS[0]-}' flag '$HOOK_JQ_FIELDS_NUL'"
fi

hook::jq_fields "$jf_nul" '.tool_input.command'
if hook::jq_fields "$jf_input" '.tool_name' && [[ "$HOOK_JQ_FIELDS_NUL" == 0 ]]; then
  ok "jq_fields: a clean payload clears the flag rather than leaving it stale"
else
  fail "jq_fields stale flag: expected 0 after a clean payload, got '$HOOK_JQ_FIELDS_NUL'"
fi

hook::jq_fields "$jf_nul" '.tool_input.command'
hook::jq_fields "$jf_nul" || true
if [[ "$HOOK_JQ_FIELDS_NUL" == 0 ]]; then
  ok "jq_fields: an early return clears the flag instead of leaking the previous call's"
else
  fail "jq_fields early-return flag: expected 0, got '$HOOK_JQ_FIELDS_NUL'"
fi

ce_probe() {
  local want="$1" desc="$2"
  shift 2
  local got
  got=$(
    # shellcheck disable=SC2016  # $0 must NOT expand here: it is the child bash's
    env -u CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED \
      "$@" bash -c 'source "$0"; hook::check_enabled "RATE_LIMITS"; printf RUN' \
      "$HOOK_DIR/hook-utils.sh" 2>/dev/null
  )
  got="${got:-SKIP}"
  if [[ "$got" == "$want" ]]; then
    ok "check_enabled: $desc"
  else
    fail "check_enabled: $desc — got '$got', want '$want'"
  fi
}

ce_probe RUN "unset stays enabled (backward compatibility)"
ce_probe RUN "explicit true" CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED=true
ce_probe SKIP "explicit false" CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED=false
ce_probe SKIP "a non-boolean value is not 'true'" CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED=yes
ce_probe RUN "empty value falls back to the default (treated as unset)" \
  CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED=

ie_probe() {
  local want="$1" desc="$2"
  shift 2
  local got
  got=$(
    # shellcheck disable=SC2016  # $0 must NOT expand here: it is the child bash's
    env -u CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED \
      "$@" bash -c 'source "$0"
        if hook::is_enabled "RATE_LIMITS"; then printf ENABLED; else printf DISABLED; fi
        printf "+SURVIVED"' "$HOOK_DIR/hook-utils.sh" 2>/dev/null
  )
  if [[ "$got" == "$want" ]]; then
    ok "is_enabled: $desc"
  else
    fail "is_enabled: $desc — got '$got', want '$want'"
  fi
}
ie_probe "ENABLED+SURVIVED" "unset returns true and does not exit"
ie_probe "ENABLED+SURVIVED" "explicit true returns true" \
  CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED=true
ie_probe "DISABLED+SURVIVED" "explicit false returns false WITHOUT exiting" \
  CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED=false

probe_lib() {
  local fn="$1" flagvar="$2" arg="$3" shim="${4:-}" probe
  probe=$(
    BASH_ENV="$shim" bash -c '
      # shellcheck source=hook-utils.sh
      source "$1"
      _tmp=$(mktemp)
      "$2" "$4" >"$_tmp"
      _rc=$?
      _flag="$3"
      printf "%s\n%s\n%s\n" "$_rc" "${!_flag}" "$(cat "$_tmp")"
      rm -f "$_tmp"
    ' _ "$HOOK_DIR/hook-utils.sh" "$fn" "$flagvar" "$arg"
  )
  {
    read -r probe_rc
    read -r probe_flag
    read -r probe_out
  } <<<"$probe"
}

physical_path_resolved() {
  local target="$1"
  probe_lib hook::physical_path HOOK_PHYSICAL_PATH_UNRESOLVED "$target"
  if ((probe_rc == 0 && probe_flag == 0)) && [[ -n "$probe_out" ]]; then
    ok "physical_path: resolved $target"
  else
    fail "physical_path: expected resolved for $target (rc=$probe_rc flag=$probe_flag out=$probe_out)"
  fi
}

physical_path_unresolved() {
  local target="$1" no_canon
  no_canon="$(mktemp)"
  cat >"$no_canon" <<'EOF'
realpath() { return 1; }
readlink() { return 1; }
enable -n cd
EOF
  probe_lib hook::physical_path HOOK_PHYSICAL_PATH_UNRESOLVED "$target" "$no_canon"
  rm -f "$no_canon"
  if ((probe_rc == 1 && probe_flag == 1)) && [[ "$probe_out" == "$target" ]]; then
    ok "physical_path: unresolved returns lexical path for $target"
  else
    fail "physical_path unresolved $target: rc=$probe_rc flag=$probe_flag out=$probe_out"
  fi
}

PP_TARGET="$(mktemp)"
printf 'probe' >"$PP_TARGET"
physical_path_resolved "$PP_TARGET"
physical_path_unresolved "$PP_TARGET"
rm -f "$PP_TARGET"

PB="$(mktemp -d)"
pb_linux=0
[[ "$(uname -s)" == Linux ]] && pb_linux=1
mkdir -p "$PB/real/sub" "$PB/a"
: >"$PB/real/f.md"
ln -s real "$PB/ln"
ln -s ../real "$PB/a/rel"
ln -s "$PB/real/f.md" "$PB/flink.md"
# shellcheck disable=SC2016  # the child's script is literal, expanded by the child
PB_OUT=$(bash -c '
  source "$1"
  PB=$2 pb_linux=$3
  for p in "$PB/ln/f.md" "$PB/ln/sub/../f.md" "$PB/a/rel/sub" "$PB/a/rel/../a" "$PB/real/sub/" /tmp/ /; do
    v=""
    if hook::_physical_builtin_to v "$p"; then
      ((pb_linux)) || echo "answered off Linux: $p"
      [[ "$v" == "$(realpath -- "$p")" ]] || echo "differs from realpath: $p = $v"
    elif ((pb_linux)); then
      echo "declined on Linux: $p"
    fi
  done
  for p in "$PB/flink.md" "$PB/missing.md" "real/f.md" "$PB//real/f.md" "$PB/real/f.md/"; do
    v=""
    hook::_physical_builtin_to v "$p" && echo "answered a declined shape: $p = $v"
  done
  v=""
  if hook::_physical_builtin_to v "$PB/ln/f.md" "$PB/ln" /tmp; then
    [[ "$v" == "$(realpath -- "$PB/ln/f.md" "$PB/ln" /tmp)" ]] || echo "batch differs: $v"
  fi
  echo pb-ok
' _ "$HOOK_DIR/hook-utils.sh" "$PB" "$pb_linux")
rm -rf "$PB"
if [[ "$PB_OUT" == pb-ok ]]; then
  ok "physical_builtin: realpath's answer or a decline, per shape"
else
  fail "physical_builtin: $PB_OUT"
fi

repo_root_resolved() {
  local hint="$1"
  probe_lib hook::repo_root HOOK_REPO_ROOT_UNRESOLVED "$hint"
  if ((probe_rc == 0 && probe_flag == 0)) && [[ -n "$probe_out" ]]; then
    ok "repo_root: git resolved from $hint"
  else
    fail "repo_root: expected git resolution from $hint (rc=$probe_rc flag=$probe_flag out=$probe_out)"
  fi
}

repo_root_unresolved() {
  local hint="$1"
  probe_lib hook::repo_root HOOK_REPO_ROOT_UNRESOLVED "$hint"
  if ((probe_rc == 1 && probe_flag == 1)) && [[ "$probe_out" == "$hint" ]]; then
    ok "repo_root: unresolved falls back to hint for $hint"
  else
    fail "repo_root unresolved $hint: rc=$probe_rc flag=$probe_flag out=$probe_out"
  fi
}

repo_root_resolved "."
RR_NOGIT="$(mktemp -d)"
repo_root_unresolved "$RR_NOGIT"
rm -rf "$RR_NOGIT"

RRP_DIR="$(mktemp -d)"
mkdir -p "$RRP_DIR/nocyg" "$RRP_DIR/cyg"
{
  printf '#!%s\n' "$BASH"
  cat <<'CYGEOF'
p=""
for a in "$@"; do p="$a"; done
_lower="abcdefghijklmnopqrstuvwxyz"
_upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
case "$p" in
/[A-Za-z]/* | /[A-Za-z])
  d="${p:1:1}"
  rest="${p:2}"
  case "$d" in
  [a-z])
    _pre="${_lower%%"$d"*}"
    d="${_upper:${#_pre}:1}"
    ;;
  *) ;;
  esac
  p="$d:$rest"
  ;;
/tmp/*/src/*)
  # Disagree with the directory's conversion on purpose, so a helper that
  # trusts cygpath alone degrades to the basename.
  p="D:/diverged/${p#/tmp/}"
  ;;
/tmp/*)
  p="C:/users/temp/${p#/tmp/}"
  ;;
*) ;;
esac
printf '%s\n' "$p"
CYGEOF
} >"$RRP_DIR/cyg/cygpath"
chmod +x "$RRP_DIR/cyg/cygpath"

rrp_case() {
  local mode="$1" label="$2" file="$3" root="$4" want="$5" want_deg="$6" probe
  # shellcheck disable=SC2031  # this shell's own OSTYPE; only the child below overrides it
  local bin="$mode" ostype="$OSTYPE"
  case "$mode" in
  cyg) ostype=msys ;;
  cygposix)
    bin=cyg
    ostype=linux-gnu
    ;;
  *) ;;
  esac
  probe=$(
    # The quoted argument is a bash script: $1, $2 and $3 are the child's own positional parameters.
    # shellcheck disable=SC2016
    PATH="$RRP_DIR/$bin" "$BASH" -c '
      OSTYPE="$4"
      # shellcheck source=hook-utils.sh
      source "$1"
      _out=""
      hook::repo_relative_path_to _out "$2" "$3"
      _rc=$?
      printf "%s\n%s\n%s\n" "$_rc" "$HOOK_REPO_RELATIVE_DEGRADED" "$_out"
    ' _ "$HOOK_DIR/hook-utils.sh" "$file" "$root" "$ostype"
  )
  local rc flag out
  {
    read -r rc
    read -r flag
    read -r out
  } <<<"$probe"
  if [[ "$out" == "$want" ]] && ((rc == want_deg)) && ((flag == want_deg)); then
    ok "repo_relative_path[$mode]: $label"
  else
    fail "repo_relative_path[$mode] $label: out=$out (want $want) rc=$rc flag=$flag (want $want_deg)"
  fi
}

rrp_case nocyg "strips the repo root" /repo/a/b.md /repo a/b.md 0
rrp_case nocyg "root mismatch redacts to basename" /elsewhere/a/b.md /repo b.md 1
rrp_case nocyg "drive-letter path redacts" 'C:/proj/app/a/b.md' /repo b.md 1
# portability-ok: a literal Windows UNC fixture path; the \s and \b are path
rrp_case nocyg "UNC path redacts on the backslash" '\\srv\share\b.md' /repo b.md 1
rrp_case nocyg "an already-relative path passes through" a/b.md /repo a/b.md 0
rrp_case nocyg "the root as the file redacts" /repo /repo repo 1
rrp_case nocyg "an empty root redacts instead of shaving the slash" /srv/proj/repo/a.txt "" a.txt 1

rrp_case cyg "mount-form file under a drive-letter root strips" /c/repo/a/b.md 'C:/repo' a/b.md 0
rrp_case nocyg "...and the same inputs degrade without cygpath (control)" /c/repo/a/b.md 'C:/repo' b.md 1
rrp_case cyg "both sides already mixed form" 'C:/repo/a/b.md' 'C:/repo' a/b.md 0
rrp_case cyg "a root mismatch still redacts through the cygpath arm" /c/elsewhere/b.md 'C:/repo' b.md 1
rrp_case cyg "an empty root redacts through the cygpath arm" /c/repo/a/b.md "" b.md 1
rrp_case cygposix "a cygpath on PATH is ignored under a Linux OSTYPE" /c/repo/a/b.md 'C:/repo' b.md 1
rrp_case cygposix "...and a POSIX strip still succeeds there" /repo/a/b.md /repo a/b.md 0
rrp_case cyg "a trailing slash on the root still strips" 'C:/repo/src/run.sh' 'C:/repo/' src/run.sh 0
rrp_case cyg "drive-letter case does not matter" 'C:/Repo/src/run.sh' 'c:/repo' src/run.sh 0
rrp_case cyg "cygpath disagreement falls back to the caller's spelling" /tmp/repo/src/run.sh /tmp/repo src/run.sh 0
rrp_case nocyg "a trailing slash on a POSIX root still strips" /repo/src/run.sh /repo/ src/run.sh 0
rrp_case cygposix "a POSIX backslash is a filename character, not a separator" '/repo\outside/secret.txt' /repo secret.txt 1

mkdir -p "$RRP_DIR/repo" "$RRP_DIR/temp"
ln -s "$RRP_DIR/repo" "$RRP_DIR/temp/to-repo"
PHYS_PROBE=$(
  # shellcheck disable=SC2016  # the child's $1 is its own positional, quoted on purpose
  PATH="$RRP_DIR/cyg" "$BASH" -c '
    OSTYPE=msys
    # shellcheck source=hook-utils.sh
    source "$1"
    _out=""
    hook::physical_path_to _out "$2"
    printf "%s\n%s\n" "$?" "$HOOK_PHYSICAL_PATH_UNRESOLVED"
  ' _ "$HOOK_DIR/hook-utils.sh" "$RRP_DIR/temp/to-repo"
)
PHYS_RC="${PHYS_PROBE%%$'\n'*}"
PHYS_FLAG="${PHYS_PROBE#*$'\n'}"
if [[ "$PHYS_RC" == 1 && "$PHYS_FLAG" == 1 ]]; then
  ok "physical_path_to: msys temp symlink with only cygpath stays unresolved"
else
  fail "physical_path_to msys cygpath-only: rc=$PHYS_RC flag=$PHYS_FLAG"
fi
rm -rf "$RRP_DIR"

bps_last=()
bps_collect() {
  bps_last=("$@")
}

bps_words_are() {
  local desc="$1"
  shift
  local want="$*"
  local got
  got="${bps_last[*]-}"
  if [[ "$got" == "$want" ]]; then
    ok "bash_parse_segments: $desc"
  else
    fail "bash_parse_segments $desc: got [$got], want [$want]"
  fi
}

hook::bash_parse_segments 'git b # -C other-repo' bps_collect
bps_words_are 'unquoted # drops trailing words' 'git b'

hook::bash_parse_segments "git '#'" bps_collect
bps_words_are 'single-quoted # preserved' "git #"

hook::bash_parse_segments 'git "#"' bps_collect
bps_words_are 'double-quoted # preserved' 'git #'

hook::bash_parse_segments 'git status; git b # -C other' bps_collect
bps_words_are 'comment only affects its segment' 'git b'

bps_all=()
bps_collect_all() {
  bps_all+=("${*}")
}

hook::bash_parse_segments 'echo x#y; git reset --hard' bps_collect_all
if [[ "${bps_all[*]-}" == "echo x#y git reset --hard" ]]; then
  ok "bash_parse_segments: mid-word # stays literal through reset"
else
  fail "bash_parse_segments mid-word # stays literal through reset: got [${bps_all[*]-}], want [echo x#y git reset --hard]"
fi

bps_segments_are() {
  local desc="$1" cmd="$2" got want
  shift 2
  bps_all=()
  hook::bash_parse_segments "$cmd" bps_collect_all
  got="$(printf '%s|' ${bps_all[@]+"${bps_all[@]}"})"
  want="$(printf '%s|' "$@")"
  if [[ "$got" == "$want" ]]; then
    ok "bash_parse_segments: $desc"
  else
    fail "bash_parse_segments $desc: got [$got], want [$want]"
  fi
}

bps_hit_dir="$WORK/bps-hit"
mkdir -p "$bps_hit_dir"
bps_bash_hit() {
  local desc="$1" h="${2//git reset --hard/"echo HIT >&2"}" m o ran=no seen=no
  for m in +O -O; do
    o=$(cd "$bps_hit_dir" && "$BASH" "$m" extglob -c "$h" 2>&1 >/dev/null </dev/null)
    [[ $'\n'"$o"$'\n' == *$'\nHIT\n'* ]] && ran=yes
  done
  o=$(
    # shellcheck disable=SC2329  # the parse callback
    bps_print() { printf '%s\n' "$*"; }
    hook::bash_parse_segments "$h" bps_print 2>/dev/null
  )
  [[ $'\n'"$o"$'\n' == *$'\necho HIT\n'* ]] && seen=yes
  if [[ "$ran" == "$seen" ]]; then
    ok "bash_parse_segments: $desc (bash runs it: $ran)"
  else
    fail "bash_parse_segments $desc: bash runs it: $ran, the reader hands it over: $seen"
  fi
}
bps_refused() {
  local desc="$1" out rc=0
  out=$(
    # shellcheck disable=SC2329  # the parse callback
    bps_print() { :; }
    hook::bash_parse_segments "$2" bps_print 2>&1
  ) || rc=$?
  if ((rc == 2)) && [[ "$out" == *'got no parse'*"$3"* ]]; then
    ok "bash_parse_segments: $desc (refused: $3)"
  else
    fail "bash_parse_segments $desc: want refused naming [$3], exit $rc, [$out]"
  fi
}

bps_refusal_is() {
  local desc="$1" out rc=0
  out=$(
    # shellcheck disable=SC2329  # the parse callback
    bps_print() { :; }
    [[ -n "$3" ]] && HOOK_BPS_SPAN=$3
    hook::bash_parse_segments "$2" bps_print 2>&1
  ) || rc=$?
  if ((rc == 2)) && [[ "$out" == "$4" ]]; then
    ok "bash_parse_segments refusal: $desc"
  else
    fail "bash_parse_segments refusal $desc: exit $rc, got [$out], want [$4]"
  fi
}
bps_xg='an extglob pattern, which shfmt and bash do not read the same way'
bps_refusal_is 'of the command itself keeps its wording' \
  '@(x)#y; git reset --hard' '' \
  "BLOCKED: the guard reads a command through shfmt and got no parse ($bps_xg), so it cannot check this call. Fix the syntax, or install shfmt and jq, then reissue the call."
bps_refusal_is 'of a lifted span names the label and shows the span' \
  $'@(x)#y;\x01\ngit reset --hard' 'guard-x: a body lifted from the command' \
  "BLOCKED: the guard reads text it lifted from the command through shfmt and got no parse ($bps_xg), so it cannot check this call. Lifted text: guard-x: a body lifted from the command. A line:col in that reason counts from the start of that text, not of the command; the text begins: \"@(x)#y; git reset --hard\". Fix the syntax there, or install shfmt and jq, then reissue the call."
bps_refusal_is 'of a lifted span caps its excerpt at 60 characters' \
  "@(x)#y; $(printf 'a%.0s' {1..80})" 'guard-x: a body' \
  "BLOCKED: the guard reads text it lifted from the command through shfmt and got no parse ($bps_xg), so it cannot check this call. Lifted text: guard-x: a body. A line:col in that reason counts from the start of that text, not of the command; the text begins: \"@(x)#y; $(printf 'a%.0s' {1..52})...\". Fix the syntax there, or install shfmt and jq, then reissue the call."
bps_refused 'a joined here-doc body reading names itself' \
  $'cat <<E\n$\\\n(\nE' \
  'an unquoted here-doc body, its backslash-newlines joined'
# shellcheck disable=SC2016  # literal backticks: each escaped pair is one more reading of the command
bps_many_bt="echo$(printf ' `: \\`:\\``%.0s' $(seq "$HOOK_BPS_MAX_PARSES"))"
bps_refused 'one more reading than the parse ceiling allows' \
  "$bps_many_bt" "more than $HOOK_BPS_MAX_PARSES parses for one command"
bps_rc=0
bps_out=$(
  # shellcheck disable=SC2329  # the inner parse callback
  bps_print() { :; }
  # shellcheck disable=SC2329  # the parse callback
  bps_reparse() {
    [[ "$1" == bash && "${2:-}" == -c ]] && hook::bash_parse_segments "$3" bps_print
    return 0
  }
  hook::bash_parse_segments $'cat <<E\n$\\\n(bash -c \'git x(\')\nE' bps_reparse 2>&1
) || bps_rc=$?
if ((bps_rc == 2)) && [[ "$bps_out" == 'BLOCKED: the guard reads a command through shfmt and got no parse ('* && "$bps_out" != *Lifted* ]]; then
  ok "bash_parse_segments refusal: a callback's parse inside a second reading names no reading"
else
  fail "bash_parse_segments refusal: a callback's parse inside a second reading: exit $bps_rc, [$bps_out]"
fi


bps_bash_hit 'array assignment ) leaves a # after it literal' \
  'a=(x)#y; git reset --hard'
bps_refused 'extglob ) leaves a # after it literal' \
  '@(x)#y; git reset --hard' \
  'an extglob pattern, which shfmt and bash do not read the same way'
bps_bash_hit '# after whitespace past an array assignment is a comment' \
  'a=(x) #; git reset --hard'
bps_segments_are 'subshell ) still starts a comment at a following #' \
  '(x)#y; git reset --hard' 'x'
bps_segments_are 'subshell ( at a word boundary still splits' \
  'true; (git reset --hard)' 'true' 'git reset --hard'
bps_refused 'extglob alternation | keeps the frame open' \
  '@(a|b)#y; git reset --hard' \
  'an extglob pattern, which shfmt and bash do not read the same way'
# shellcheck disable=SC2016  # the backticks are shfmt's message text
bps_refused 'f@()# yields the extglob-on word reading, then the function-definition comment' \
  'f@()#y; git reset --hard' \
  '`foo()` must be followed by a statement'
bps_refused 'bare !(x)# yields the extglob-on word reading, then the negated-subshell comment' \
  '!(x)#; git reset --hard' \
  'an extglob pattern, which shfmt and bash do not read the same way'
bps_refused 'the extglob-on reading keeps a second # in the word' \
  '!(x)##; git reset --hard' \
  'an extglob pattern, which shfmt and bash do not read the same way'
bps_refused 'the extglob-on reading runs past the line: a quote it opens can close later' \
  $'!(x)#\'\n\'; git reset --hard' \
  'an extglob pattern, which shfmt and bash do not read the same way'
bps_refused 'the extglob-on reading keeps a pending here-doc body out of commands' \
  $'cat <<EOF; !(x)#; :\ngit reset --hard\nEOF\necho done' \
  'an extglob pattern, which shfmt and bash do not read the same way'
bps_refused 'a backslash-newline after !(x)# keeps the extglob refusal' \
  $'!(x)#; git \\\nreset --hard' \
  'an extglob pattern, which shfmt and bash do not read the same way'
# shellcheck disable=SC2016  # the substitutions are the command text under test
{
  bps_bash_hit '$(…) ) leaves a # after it literal' \
    'echo $(:)#; git reset --hard'
  bps_bash_hit '$((…)) ) leaves a # after it literal' \
    'echo $((1))#; git reset --hard'
  bps_bash_hit 'a ; inside $(…) keeps its frame' \
    'echo $(:;:)#; git reset --hard'
  bps_bash_hit 'a newline inside $(…) keeps its frame' \
    $'echo $(:\n:)#; git reset --hard'
  bps_bash_hit 'a case pattern ) inside $(…) pops no frame' \
    'echo $(case x in x) :;; esac)#; git reset --hard'
  bps_bash_hit 'a # after a case pattern ) inside $(…) is a comment' \
    $'a=($(case x in x)#\'\ngit reset --hard;; esac))'
  bps_bash_hit '# after whitespace past $(…) is a comment' \
    'echo $(:) #; git reset --hard'
  bps_bash_hit 'closing backtick leaves a # after it literal' \
    'echo `:`#; git reset --hard'
  bps_bash_hit 'a ; inside backticks keeps the frame' \
    'echo `:;:`#; git reset --hard'
  bps_bash_hit 'a comment inside backticks ends at the closing backtick' \
    'echo `#`; git reset --hard'
  bps_bash_hit 'an escaped backtick inside a backtick comment does not close it' \
    $'echo `# \\`; git reset --hard\n:`'
  bps_refused 'a backtick after an escaped backslash closes the substitution' \
    $'echo `# \\\\`; git reset --hard\n:`' \
    'reached EOF without closing quote "`"'
  bps_bash_hit 'case inside $((…)) is a variable, not a case statement' \
    'echo $((case))#; git reset --hard'
  bps_refused 'esac inside $((…)) closes no case frame' \
    'case x in x) echo $((esac))#; git reset --hard;; esac' \
    '`case` statement must end with `esac`'
  bps_bash_hit 'a ( group inside $((…)) keeps the arithmetic frame' \
    'echo $(( (1) ))#; git reset --hard'
  bps_bash_hit 'a $(…) inside $((…)) is a command context again' \
    'echo $(( $(case x in x) echo 1;; esac) ))#; git reset --hard'
  bps_bash_hit '# after a ((…)) command is a comment' \
    '((case))#; git reset --hard'
  bps_bash_hit 'a case pattern spelled case after ;; opens no case frame' \
    'echo $(case x in x) :;; case) :;; esac)#; git reset --hard'
  bps_bash_hit 'a case pattern spelled case after a newline opens no case frame' \
    $'echo $(case x in\ncase) :;; esac)#; git reset --hard'
  bps_bash_hit 'a case pattern in parentheses spelled case opens no case frame' \
    'echo $(case x in (case) :;; esac)#; git reset --hard'
  bps_refused "a \$'…' inside backticks ends at the closing backtick" \
    "echo \`\$'\`; git reset --hard #'\`" \
    'backticks bash would end at a different backtick'
  bps_refused 'a quoted here-doc delimiter inside backticks ends at the closing backtick' \
    "echo \`cat <<'\`; git reset --hard #'\`" \
    'unclosed here-document "`; git reset --hard #"'
  bps_refused 'a here-doc opened inside backticks takes no body after them' \
    $'echo `cat <<E`\ngit reset --hard\nE' \
    'a here-doc opened inside backticks, which bash reads differently'
  bps_bash_hit 'an esac after | in a case pattern is a pattern word' \
    'echo $(case x in a|esac) :;; esac)#; git reset --hard'
  bps_bash_hit 'an esac right after in closes the case' \
    'echo $(case x in esac)#; git reset --hard'
  bps_bash_hit 'an escaped ; before a ; is a word, not a clause end' \
    'echo $(case x in x) \;; case y in y) :;; esac;; z) :;; esac)#; git reset --hard'
  bps_bash_hit 'an escaped backtick inside backticks opens a nested substitution' \
    'echo `echo \`git reset --hard\``'
  bps_bash_hit 'escaped backticks two levels deep open a nested substitution' \
    'echo `echo \`echo \\\`git reset --hard\\\`\``'
  bps_bash_hit 'a # right after a nested substitution is literal' \
    'echo `echo \`:\`#; git reset --hard`'
  bps_segments_are 'an escaped backtick outside backticks stays a literal character' \
    'echo \`; git reset --hard' 'echo `' 'git reset --hard'
  bps_refused 'a here-doc body inside backticks ends at the closing backtick' \
    $'echo `cat <<E\nx`\ngit reset --hard\nE' \
    'unclosed here-document `E`'
}

bps_heredocs_are() {
  local desc="$1" cmd="$2" got want
  shift 2
  bps_all=()
  hook::bash_parse_segments "$cmd" bps_collect_all
  got="$(printf '%s|' ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"})"
  want="$(printf '%s|' "$@")"
  if [[ "$got" == "$want" ]]; then
    ok "bash_parse_segments: $desc"
  else
    fail "bash_parse_segments $desc: got [$got], want [$want]"
  fi
}
bps_refused 'a here-doc both extglob readings would see is refused with the extglob' \
  $'cat <<EOF; !(x)#; :\nbody\nEOF\necho done' \
  'an extglob pattern, which shfmt and bash do not read the same way'
bps_refused 'a [[ =~ ]] regex group keeps a pending here-doc' \
  $'cat <<E; [[ $s =~ k=(a|b) ]]\nit\'s\nE\ngit reset --hard' \
  reached\ EOF\ without\ closing\ quote\ \`\'\`
# shellcheck disable=SC2016  # the substitutions are the command text under test
{
  bps_bash_hit 'a pattern word that starts with $(…) is the first pattern word' \
    'echo $(case x in $(:)|esac) :;; esac)#; git reset --hard'
  bps_refused 'a ((…) ) that is not arithmetic is a nested subshell' \
    "((bash <<< 'rm -rf ~') )" \
    '`<<` must be followed by an expression'
}
# bps_redirs_are <desc> <command> <op target>...: every redirection reported.
# shellcheck disable=SC2329  # invoked indirectly as the parse callback
bps_redir_collect() {
  local r
  for ((r = 0; r < ${#HOOK_SEG_REDIR_OP[@]}; r++)); do
    bps_all+=("${HOOK_SEG_REDIR_OP[r]} ${HOOK_SEG_REDIR_TARGET[r]}")
  done
}
bps_redirs_are() {
  local desc="$1" cmd="$2" got want
  shift 2
  bps_all=()
  hook::bash_parse_segments "$cmd" bps_redir_collect
  got="$(printf '%s|' ${bps_all[@]+"${bps_all[@]}"})"
  want="$(printf '%s|' "$@")"
  if [[ "$got" == "$want" ]]; then
    ok "bash_parse_segments: $desc"
  else
    fail "bash_parse_segments $desc: got [$got], want [$want]"
  fi
}
# shellcheck disable=SC2016  # the backticks are shfmt's message text
bps_refused 'a here-string inside a ((…) ) subshell is a redirection' \
  "((bash <<< 'rm -rf ~') )" \
  '`<<` must be followed by an expression'
# shellcheck disable=SC2016  # the substitution is the command text under test
bps_refused 'a here-string inside a $((…) ) substitution is a redirection' \
  "echo \$((bash <<< 'rm -rf ~') )" \
  '`<<` must be followed by an expression'
# shellcheck disable=SC2016  # the backticks are shfmt's message text
bps_refused 'a write inside a ((…) ) subshell is a redirection' \
  '((cat f > ../other/x) )' \
  'not a valid arithmetic operator: `f`'
bps_refused 'a here-doc read before a backtick takes its body after the backtick line' \
  $'cat <<A; echo `:\ngit reset --hard`\nA' \
  'a here-doc body that starts inside backticks, which bash reads differently'
bps_refused 'here-docs from both extglob readings come in source order' \
  $'!(x)#\'\ncat <<B\nb\nB\n\' ; cat <<C\nc\nC' \
  'an extglob pattern, which shfmt and bash do not read the same way'
bps_refused 'a quote inside backticks ends at the closing backtick' \
  "echo \`'\`; git reset --hard #'" \
  'reached EOF without closing quote "`"'
bps_bash_hit 'process substitution ) leaves a # after it literal' \
  'cat <(:)#; git reset --hard'
bps_refused 'a ; inside an extglob keeps its frame' \
  'echo @(x;y)#; git reset --hard' \
  'an extglob pattern, which shfmt and bash do not read the same way'
bps_bash_hit 'a newline inside an array assignment keeps its frame' \
  $'a=(x\ny)#; git reset --hard'
# shellcheck disable=SC2016  # the substitution is the command text under test
bps_bash_hit 'substitution inside an array assignment stays a segment' \
  'a=($(git reset --hard))#y'
# shellcheck disable=SC2016  # the parameter expansion is the command text under test
bps_refused '( inside an open ${...} opens no word-continuing frame' \
  'echo ${x#*(}; case x in x)#y' \
  '`case` statement must end with `esac`'

bps_or_tmp=$(mktemp -d)
bps_oracle() {
  local m out serr=0 w=0
  bps_or_hit=0 bps_or_wrote=0
  [[ "$1" == *hook-oracle-w* ]] && w=1
  for m in +O -O; do
    rm -f "$bps_or_tmp/hook-oracle-w"
    out=$(cd "$bps_or_tmp" && exec bash "$m" extglob -c "$1" 2>&1 >/dev/null </dev/null)
    [[ $'\n'"$out"$'\n' == *$'\nHIT\n'* ]] && bps_or_hit=1
    [[ -e "$bps_or_tmp/hook-oracle-w" ]] && bps_or_wrote=1
    [[ "$out" == *'syntax error'* ]] && serr=$((serr + 1))
    ((bps_or_hit && (bps_or_wrote || !w))) && return 0
  done
  ((!bps_or_hit && !bps_or_wrote && serr == 2)) && return 2
  return 0
}
# shellcheck disable=SC2016  # the substitutions are the command text under test
{
  bps_or_ipre=('$(' '$((' '$((' '((' '((' '<(' '`' 'a=(' '@(' '[[ x =~ k=(' '[[ x =~ (')
  bps_or_ipost=(')' '))' ') )' '))' ') )' ')' '`' ')' ')' ') ]]' ') ]]')
  bps_or_pre=('echo $(' 'echo $((' '((' '((' 'echo $((' 'cat <(' 'echo `' 'a=('
    'echo @(' '[[ x =~ k=(' '[[ x =~ ('
    'echo $(case x in ' $'echo $(case x in\n' 'echo $(case x in a|'
    'echo $(case x in a) :;; ' 'echo $(case x in a) :;& ' 'echo $(case x in a) :;;& '
    'echo $(case x in (' 'echo $(case x in ' 'echo $(case x in a) :;; '
    'echo $(case x in a) ' 'echo $(case x in a) '
    'echo $(case x in ' 'echo $(case x in a) :;; ')
  bps_or_post=(')' '))' '))' ') )' ') )' ')' '`' ')'
    ')' ') ]]' ') ]]'
    ') :;; esac)' ') :;; esac)' ') :;; esac)'
    ') :;; esac)' ') :;; esac)' ') :;; esac)'
    ') :;; esac)' ')' ')'
    ';; esac)' ' case y in y) :;; esac;; z) :;; esac)'
    '|esac) :;; esac)' '|esac) :;; esac)')
  bps_or_words=('case' 'esac' 'in' '\;;' '\)' '\`' '")"' '#' '<<E'
    ':>hook-oracle-w' 'a|b' 'x<y')
  bps_or_before=('' ': ' '' '')
  bps_or_after=('' '' $'\n:' $'\necho HIT >&2\n')
  bps_or_leads=('' 'cat <<E; ')
  bps_or_tails=('#; echo HIT >&2' $'\necho HIT >&2' $'\nit\'s\nE\necho HIT >&2')
}
bps_or_print() {
  printf 'S%s\1' "$*"
  local t
  for t in ${HOOK_SEG_REDIR_TARGET[@]+"${HOOK_SEG_REDIR_TARGET[@]}"}; do printf 'T%s\1' "$t"; done
}
bps_oracle_row() {
  local rc=0 s seen=0 out err
  bps_or_n=$((bps_or_n + 1))
  bps_oracle "$1" || rc=$?
  if ((rc == 2)); then
    bps_or_skip=$((bps_or_skip + 1))
    return 0
  fi
  ((bps_or_hit || bps_or_wrote)) || return 0
  bps_or_ran=$((bps_or_ran + bps_or_hit))
  bps_or_wrote_n=$((bps_or_wrote_n + bps_or_wrote))
  bps_all=()
  bps_or_tg=()
  rc=0
  out=$(hook::bash_parse_segments "$1" bps_or_print 2>"$bps_or_tmp/parse.err") || rc=$?
  err=$(<"$bps_or_tmp/parse.err")
  if ((rc == 2)) && [[ "$err" == BLOCKED:* ]]; then
    bps_or_refused=$((bps_or_refused + 1))
    return 0
  fi
  if ((rc != 0)); then
    bps_or_bad=$((bps_or_bad + 1))
    fail "bash_parse_segments oracle: the parse exited $rc (${err:0:200}): $(printf '%q' "$1")"
    return 0
  fi
  while [[ -n "$out" ]]; do
    s=${out%%$'\1'*}
    out=${out#*$'\1'}
    case "$s" in
    S*) bps_all+=("${s#S}") ;;
    T*) bps_or_tg+=("${s#T}") ;;
    *) ;;
    esac
  done
  if ((bps_or_hit)); then
    for s in ${bps_all[@]+"${bps_all[@]}"}; do
      [[ "$s" == 'echo HIT' ]] && seen=1
    done
    if ((!seen)); then
      bps_or_bad=$((bps_or_bad + 1))
      fail "bash_parse_segments oracle: bash runs HIT but the parser hides it: $(printf '%q' "$1")"
    fi
  fi
  if ((bps_or_wrote)); then
    seen=0
    for s in ${bps_or_tg[@]+"${bps_or_tg[@]}"}; do
      [[ "$s" == 'hook-oracle-w' ]] && seen=1
    done
    if ((!seen)); then
      bps_or_bad=$((bps_or_bad + 1))
      fail "bash_parse_segments oracle: bash writes hook-oracle-w but the parser reports no such redirect: $(printf '%q' "$1")"
    fi
  fi
}
bps_oracle_cell() {
  local p w t l
  for ((p = 0; p < ${#bps_or_before[@]}; p++)); do
    for w in "${bps_or_words[@]}"; do
      for t in "${bps_or_tails[@]}"; do
        for l in "${bps_or_leads[@]}"; do
          bps_or_all=$((bps_or_all + 1))
          (((bps_or_all * 40503) % 65536 < bps_or_keep)) || continue
          bps_oracle_row "$l$1${bps_or_before[p]}$w${bps_or_after[p]}$2$t"
        done
      done
    done
  done
}
bps_or_n=0 bps_or_ran=0 bps_or_wrote_n=0 bps_or_skip=0 bps_or_bad=0 bps_or_all=0 bps_or_refused=0
bps_or_t0=$SECONDS
bps_or_keep1=65536 bps_or_keep2=2048
# shellcheck disable=SC2031  # this shell's own OSTYPE; Test 11 overrides it only in subshells
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
  bps_or_keep1=6554 bps_or_keep2=512
fi
bps_or_keep=$bps_or_keep1
for ((bps_or_k = 0; bps_or_k < ${#bps_or_pre[@]}; bps_or_k++)); do
  bps_oracle_cell "${bps_or_pre[bps_or_k]}" "${bps_or_post[bps_or_k]}"
done
bps_or_n1=$bps_or_n bps_or_all1=$bps_or_all
bps_or_keep=$bps_or_keep2
for ((bps_or_k = 0; bps_or_k < ${#bps_or_pre[@]}; bps_or_k++)); do
  for ((bps_or_m = 0; bps_or_m < ${#bps_or_ipre[@]}; bps_or_m++)); do
    [[ "${bps_or_post[bps_or_k]}" == '`' && "${bps_or_ipost[bps_or_m]}" == '`' ]] && continue
    bps_oracle_cell "${bps_or_pre[bps_or_k]}${bps_or_ipre[bps_or_m]}" \
      "${bps_or_ipost[bps_or_m]}${bps_or_post[bps_or_k]}"
  done
done
rm -rf "${bps_or_tmp:?}"
if ((bps_or_ran == 0 || bps_or_wrote_n == 0)); then
  fail "bash_parse_segments oracle: bash ran HIT in $bps_or_ran rows and wrote the file in $bps_or_wrote_n, so the table checks too little"
elif ((bps_or_bad == 0)); then
  ok "bash_parse_segments oracle: depth 1 $bps_or_n1 of $bps_or_all1 rows, depth 2 $((bps_or_n - bps_or_n1)) of $((bps_or_all - bps_or_all1)) sampled; $bps_or_ran run HIT and $bps_or_wrote_n write in bash, $bps_or_skip syntax errors skipped, $bps_or_refused refused by the reader, none hidden ($((SECONDS - bps_or_t0)) s)"
fi

bps_acd_cmd='git commit -m $'"'"'hello\nworld'"'"
hook::bash_parse_segments "$bps_acd_cmd" bps_collect
if [[ "${bps_last[0]-}" == git && "${bps_last[1]-}" == commit && "${bps_last[2]-}" == -m && "${bps_last[3]-}" == $'hello\nworld' ]]; then
  ok "bash_parse_segments: ANSI-C \$'…' decodes newline"
else
  fail "bash_parse_segments ANSI-C: got [${bps_last[*]-}]"
fi
acd_to=""
hook::ansi_c_decode_to acd_to 'tab\tx'
if [[ "$acd_to" == $'tab\tx' ]]; then
  ok "ansi_c_decode_to: writes the decoded body in-process"
else
  fail "ansi_c_decode_to: got $(printf %q "$acd_to")"
fi
acd_nl=""
hook::ansi_c_decode_to acd_nl 'a\nb'
if [[ "$acd_nl" == $'a\nb' ]]; then
  ok "ansi_c_decode_to: decodes a newline escape"
else
  fail "ansi_c_decode_to newline: got $(printf %q "$acd_nl")"
fi

acd_pin_dir="$(mktemp -d)"
acd_pin_file="$acd_pin_dir/pids"
eval "$(declare -f hook::ansi_c_decode_to | sed '1s/^hook::ansi_c_decode_to/__pin_acd_to/')"
hook::ansi_c_decode_to() {
  printf 'acd %s %s\n' "$$" "$BASHPID" >>"$acd_pin_file"
  __pin_acd_to "$@"
}
hook::bash_parse_segments "$bps_acd_cmd" bps_collect
if grep -q "^acd $$ $$" "$acd_pin_file"; then # portability-ok: grep -q quiet match, not grep -P
  ok "bash_parse_segments: ansi_c_decode_to runs in-process"
else
  fail "bash_parse_segments ansi_c_decode_to not in-process: $(tr '\n' ';' <"$acd_pin_file")"
fi
eval "$(declare -f __pin_acd_to | sed '1s/^__pin_acd_to/hook::ansi_c_decode_to/')"
rm -rf "$acd_pin_dir"

bps_redir_seen=()
bps_redir_collect() {
  local rec="ARGV:$*" j
  for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
    rec+=" R:${HOOK_SEG_REDIR_OP[j]}|${HOOK_SEG_REDIR_FD[j]}|${HOOK_SEG_REDIR_TARGET[j]}"
    rec+="|${HOOK_SEG_REDIR_QUOTED[j]}|${HOOK_SEG_REDIR_OPAQUE[j]}"
  done
  bps_redir_seen+=("$rec")
}

bps_redir_case() {
  local desc="$1" cmd="$2"
  shift 2
  bps_redir_seen=()
  hook::bash_parse_segments "$cmd" bps_redir_collect
  local want="$*" got="${bps_redir_seen[*]-}"
  if [[ "$got" == "$want" ]]; then
    ok "bash_parse_segments redirections: $desc"
  else
    fail "bash_parse_segments redirections $desc: got [$got], want [$want]"
  fi
}

bps_redir_case 'quoted operand carrying whitespace stays one target' \
  'echo x > "/dev/null ../../etc/pw"' \
  'ARGV:echo x R:>||/dev/null ../../etc/pw|1|0'
# shellcheck disable=SC2016  # the backticks are shfmt's message text
bps_refused 'here-doc opener with a redirect glued to the delimiter, no body' \
  'cat <<EOF>file' \
  'unclosed here-document `EOF`'
# `)` is a metacharacter, so it ends the delimiter word as it does in bash.
# shellcheck disable=SC2016  # the backticks are shfmt's message text
bps_refused 'here-doc delimiter ended by a closing parenthesis, no body' \
  "(cat <<'E')" \
  'unclosed here-document `E`'
bps_redir_case 'fd dup then a stdout redirect' \
  'echo x 2>&1 > file' \
  'ARGV:echo x R:>&|2|1|0|0 R:>||file|0|0'
bps_redir_case 'escaped separator keeps the redirect in the same segment' \
  'echo x \; > f' \
  'ARGV:echo x ; R:>||f|0|0'
# A here-string whose quote never closes is a syntax error: refused.
# shellcheck disable=SC2016  # the backticks are shfmt's message text
bps_refused 'unterminated here-string' \
  'read x <<<"abc' \
  'reached EOF without closing quote `"`'
bps_redir_case 'redirect ahead of the command word' \
  '>file echo x' \
  'ARGV:echo x R:>||file|0|0'
bps_redir_case 'append plus a separate stderr redirect' \
  'echo x >>f 2>err' \
  'ARGV:echo x R:>>||f|0|0 R:>|2|err|0|0'

bps_word_q=""
bps_word_q_collect() {
  bps_word_q="${HOOK_SEG_WORD_QUOTED[*]}"
}
hook::bash_parse_segments 'cat "a" b\ c' bps_word_q_collect
if [[ "$bps_word_q" == "0 2 1" ]]; then
  ok "bash_parse_segments: per-word quoting provenance"
else
  fail "bash_parse_segments per-word quoting provenance: got [$bps_word_q], want [0 2 1]"
fi

bps_hd_case() { # <desc> <command> <want entries joined by |>
  hook::bash_parse_segments "$2" bps_collect
  local got
  got=$(join_a ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"})
  if [[ "$got" == "$3" ]]; then
    ok "bash_parse_segments heredoc bodies: $1"
  else
    fail "bash_parse_segments heredoc bodies $1: got [$got], want [$3]"
  fi
}
bps_hd_case "three on one line: quoted, <<- double-quoted, unquoted" \
  $'cat <<\'A\' <<-"B" <<C\na\nA\n\tb\n\tB\nc\nC\necho done' '21 25 1 1 A|25 31 1 1 B|31 35 0 1 C'
# shellcheck disable=SC2016  # the backticks are shfmt's message text
bps_refused "a body with no delimiter line" $'cat <<\\EOF\nx' 'unclosed here-document `EOF`'
bps_hd_case "an opener inside double quotes is not one" $'echo "<<\'EOF\'"\nx\nEOF' ''
bps_hd_case "a multibyte body is counted in bytes" $'cat <<\'E\'\né\nE\n' '10 15 1 1 E'
bps_hd_case "a closing parenthesis ends the delimiter" $'(cat <<\'E\')\nx\nE\necho done' '12 16 1 1 E'

bps_mb_case() { # <desc> <command> <want words joined by |>
  bps_last=()
  hook::bash_parse_segments "$2" bps_collect
  local got
  got=$(join_a ${bps_last[@]+"${bps_last[@]}"})
  if [[ "$got" == "$3" ]]; then
    ok "bash_parse_segments bytes: $1"
  else
    fail "bash_parse_segments bytes $1: got [$(printf %q "$got")], want [$(printf %q "$3")]"
  fi
}
bps_mb_run() {
  bps_mb_case "multibyte words survive the byte walk" \
    'echo "héllo wörld ✓" 日本語 𝄞' 'echo|héllo wörld ✓|日本語|𝄞'
  bps_refused "an invalid UTF-8 byte" \
    $'printf \xff\xfe \xc3' 'invalid UTF-8 encoding'
  bps_mb_case "a multibyte heredoc body is skipped, the next line parsed" \
    $'cat <<EOF\nünï ✓\nEOF\necho après' 'echo|après'
  local mb='é日' before
  before=${#mb}
  hook::bash_parse_segments 'echo é' bps_collect
  if [[ "${#mb}" == "$before" ]]; then
    ok "bash_parse_segments: the caller's locale is restored"
  else
    fail "bash_parse_segments: locale leaked, \${#mb} $before -> ${#mb}"
  fi
}
bps_mb_in() { # <LC_ALL value, empty for unset> -> bps_mb_run there, then the LC_ALL check
  (
    # shellcheck disable=SC2030,SC2031
    if [[ -n "$1" ]]; then declare -x LC_ALL="$1"; else unset LC_ALL; fi
    bps_mb_run
    local now
    now=$(declare -p LC_ALL 2>/dev/null)
    if [[ -z "$1" && -z "$now" ]]; then
      ok "bash_parse_segments: an unset LC_ALL stays unset"
    elif [[ -n "$1" && "$now" == "declare -x LC_ALL=\"$1\"" ]]; then
      ok "bash_parse_segments: LC_ALL=$1 keeps its value and export flag"
    else
      fail "bash_parse_segments: LC_ALL [${1:-unset}] came back as [${now:-unset}]"
    fi
  )
}
bps_mb_in ""
bps_mb_in C.UTF-8

bps_lin_ms() { # <command> -> best of three parse times, in microseconds
  local best=-1 t0 t1 d _r
  for _r in 1 2 3; do
    t0=$EPOCHREALTIME
    hook::bash_parse_segments "$1" :
    t1=$EPOCHREALTIME
    d=$((${t1/./} - ${t0/./}))
    ((best < 0 || d < best)) && best=$d
  done
  printf '%s' "$best"
}
if [[ -z "${EPOCHREALTIME:-}" ]]; then
  ok "bash_parse_segments linear cost: not timed (EPOCHREALTIME absent, Bash < 5.0)"
else
  bps_lin_line='git commit -m "ünïcödé prose, again" && echo ok; '
  bps_lin_small=""
  while ((${#bps_lin_small} < 2000)); do bps_lin_small+="$bps_lin_line"; done
  bps_lin_large=""
  for _ in 1 2 3 4 5 6 7 8; do bps_lin_large+="$bps_lin_small"; done
  (
    # shellcheck disable=SC2031
    declare -x LC_ALL=C.UTF-8
    small=$(bps_lin_ms "$bps_lin_small")
    large=$(bps_lin_ms "$bps_lin_large")
    ((small > 0)) || small=1
    ratio=$((large / small))
    if ((ratio < 20)); then
      ok "bash_parse_segments: 8x the command costs ${ratio}x (${small} us -> ${large} us)"
    else
      fail "bash_parse_segments: 8x the command costs ${ratio}x (${small} us -> ${large} us); the walk is superlinear again"
    fi
  )
fi

rr_to=""
hook::repo_root_to rr_to "."
rr_print=$(hook::repo_root ".")
if [[ -n "$rr_to" && "$rr_to" == "$rr_print" ]]; then
  ok "repo_root_to: matches print form"
else
  fail "repo_root_to: to=$(printf %q "$rr_to") print=$(printf %q "$rr_print")"
fi
rp_to=""
HOOK_REPO_RELATIVE_DEGRADED=1
hook::repo_relative_path_to rp_to "/repo/a/b.md" "/repo" || true
if [[ "$rp_to" == "a/b.md" && "${HOOK_REPO_RELATIVE_DEGRADED:-1}" == "0" ]]; then
  ok "repo_relative_path_to: strips in-process"
else
  fail "repo_relative_path_to: got $(printf %q "$rp_to") degraded=${HOOK_REPO_RELATIVE_DEGRADED-}"
fi
rp_deg=""
HOOK_REPO_RELATIVE_DEGRADED=0
hook::repo_relative_path_to rp_deg "/elsewhere/a/b.md" "/repo" || true
if [[ "$rp_deg" == "b.md" && "${HOOK_REPO_RELATIVE_DEGRADED:-0}" == "1" ]]; then
  ok "repo_relative_path_to: degraded basename is distinguishable"
else
  fail "repo_relative_path_to degraded: got $(printf %q "$rp_deg") flag=${HOOK_REPO_RELATIVE_DEGRADED-}"
fi

pin_dir="$(mktemp -d)"
pin_file="$pin_dir/pids"
eval "$(declare -f hook::resolve_read_timeout_to | sed '1s/^hook::resolve_read_timeout_to/__pin_timeout_to/')"
eval "$(declare -f hook::resolve_read_slice_to | sed '1s/^hook::resolve_read_slice_to/__pin_slice_to/')"
hook::resolve_read_timeout_to() {
  printf 'timeout %s %s\n' "$$" "$BASHPID" >>"$pin_file"
  __pin_timeout_to "$@"
}
hook::resolve_read_slice_to() {
  printf 'slice %s %s\n' "$$" "$BASHPID" >>"$pin_file"
  __pin_slice_to "$@"
}
hook::buffer_stdin >/dev/null <<'PIN_PAYLOAD'
{"ok":true}
PIN_PAYLOAD
if grep -q "^timeout $$ $$" "$pin_file" && grep -q "^slice $$ $$" "$pin_file"; then # portability-ok: grep -q quiet match, not grep -P
  ok "buffer_stdin: resolve_*_to run in-process (no wrapper subshell)"
else
  fail "buffer_stdin resolve_*_to not in-process: $(tr '\n' ';' <"$pin_file")"
fi
eval "$(declare -f __pin_timeout_to | sed '1s/^__pin_timeout_to/hook::resolve_read_timeout_to/')"
eval "$(declare -f __pin_slice_to | sed '1s/^__pin_slice_to/hook::resolve_read_slice_to/')"
rm -rf "$pin_dir"

for retired_fn in \
  hook::normalize_path hook::expand_8dot3 hook::json_escape_jq \
  hook::repo_relative_path hook::resolve_read_timeout hook::resolve_read_slice \
  hook::ansi_c_decode hook::emit_additional_context; do
  if declare -F "$retired_fn" >/dev/null 2>&1; then
    fail "retired print form is defined again: $retired_fn"
  else
    ok "retired print form stays retired: $retired_fn"
  fi
done

bs_to=""
bs_to_file="$(mktemp)"
hook::buffer_stdin_to bs_to >"$bs_to_file" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git status --short"}}
EOF
bs_to_rc=$?
if ((bs_to_rc == 0)) && [[ ! -s "$bs_to_file" ]] && [[ "$bs_to" == *$'"tool_name":"Bash"'* ]]; then
  ok "buffer_stdin_to: writes dest, prints nothing"
else
  fail "buffer_stdin_to dest: rc=$bs_to_rc outlen=$(wc -c <"$bs_to_file") dest=$(printf %q "$bs_to")"
fi
rm -f "$bs_to_file"

bs_print_file="$(mktemp)"
bs_to_dump="$(mktemp)"
hook::buffer_stdin >"$bs_print_file" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git status --short"}}
EOF
printf '%s' "$bs_to" >"$bs_to_dump"
if cmp -s "$bs_print_file" "$bs_to_dump"; then
  ok "buffer_stdin print form matches buffer_stdin_to dest"
else
  fail "buffer_stdin print/to mismatch"
fi
rm -f "$bs_print_file" "$bs_to_dump"

HOOK_JQ_FIELDS=()
HOOK_JQ_FIELDS_NUL=1
bs_fused=""
hook::buffer_stdin_to bs_fused '.tool_input.command' '.tool_name' <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git status --short"}}
EOF
bs_fused_rc=$?
if ((bs_fused_rc == 0)) && [[ "$bs_fused" == "$bs_to" ]] &&
  [[ "${HOOK_JQ_FIELDS[0]}" == "git status --short" && "${HOOK_JQ_FIELDS[1]}" == "Bash" && "$HOOK_JQ_FIELDS_NUL" == "0" ]]; then
  ok "buffer_stdin_to fused filters populate HOOK_JQ_FIELDS"
else
  fail "buffer_stdin_to fused: rc=$bs_fused_rc dest=$(printf %q "$bs_fused") fields=(${HOOK_JQ_FIELDS[*]-}) nul=$HOOK_JQ_FIELDS_NUL"
fi

bs_cut=""
bs_cut_err=$(hook::buffer_stdin_to bs_cut '.tool_name' <<<'{"incomplete":' 2>&1)
bs_cut_rc=$?
if ((bs_cut_rc == 3)) && [[ -z "$bs_cut" ]] && [[ "$bs_cut_err" == *"cut short"* ]] && [[ "$bs_cut_err" != *"BLOCKED"* ]]; then
  ok "buffer_stdin_to fused truncated JSON at EOF is cut short"
else
  fail "buffer_stdin_to fused truncated: rc=$bs_cut_rc err=$(printf %q "$bs_cut_err")"
fi
bs_bad=""
bs_bad_err=$(hook::buffer_stdin_to bs_bad '.tool_name' <<<'not json' 2>&1)
bs_bad_rc=$?
if ((bs_bad_rc == 2)) && [[ "$bs_bad_err" == *"not valid JSON"* ]] && [[ "$bs_bad_err" != *"cut short"* ]]; then
  ok "buffer_stdin_to fused malformed JSON fails closed"
else
  fail "buffer_stdin_to fused malformed: rc=$bs_bad_rc err=$(printf %q "$bs_bad_err")"
fi

input="sentinel"
read_timeout="sentinel"
fields_rc="sentinel"
hook::buffer_stdin_to input <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git status --short"}}
EOF
input_rc=$?
hook::buffer_stdin_to read_timeout <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git status --short"}}
EOF
hook::buffer_stdin_to fields_rc '.tool_input.command' '.tool_name' <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git status --short"}}
EOF
if ((input_rc == 0)) && [[ "$input" == "$bs_to" && "$read_timeout" == "$bs_to" && "$fields_rc" == "$bs_to" ]]; then
  ok "buffer_stdin_to: dest names matching internals still receive the payload"
else
  fail "buffer_stdin_to dest-collision: input=$(printf %q "$input") read_timeout=$(printf %q "$read_timeout") fields_rc=$(printf %q "$fields_rc")"
fi

jso_want=$(jq -nc --arg tool Bash --arg subject "git status --short" --arg form "" \
  '{tool:$tool,subject:$subject,form:$form}')
jso_want="${jso_want//$'\r'/}"
jso_got=""
hook::json_str_object_to jso_got tool Bash subject "git status --short" form ""
if [[ "$jso_got" == "$jso_want" ]]; then
  ok "json_str_object_to: matches jq -nc for {tool,subject,form}"
else
  fail "json_str_object_to: got [$jso_got] want [$jso_want]"
fi
jso_esc_want=$(jq -nc --arg tool Bash --arg subject 'a"b\c' --arg form $'x\ny' \
  '{tool:$tool,subject:$subject,form:$form}')
jso_esc_want="${jso_esc_want//$'\r'/}"
jso_esc_got=""
hook::json_str_object_to jso_esc_got tool Bash subject 'a"b\c' form $'x\ny'
if [[ "$jso_esc_got" == "$jso_esc_want" ]]; then
  ok "json_str_object_to: matches jq escapes for quote, backslash, newline"
else
  fail "json_str_object_to escapes: got [$jso_esc_got] want [$jso_esc_want]"
fi

tr_shim="$(mktemp -d)"
tr_log="$tr_shim/log"
if make_logging_shim "$tr_shim" tr; then
  PATH="$tr_shim:$PATH" hook::json_escape $'a\001b"c' >/dev/null
  if [[ -f "$tr_log" ]]; then
    fail "json_escape spawned tr ($(wc -l <"$tr_log") times)"
  else
    ok "json_escape: drops C0 in-shell, does not exec tr"
  fi
  : >"$tr_log"
  notice_data="$(mktemp -d)"
  PATH="$tr_shim:$PATH" CLAUDE_PLUGIN_DATA="$notice_data" \
    hook::notice_once "k-tr" '{"session_id":"s","hook_event_name":"PostToolUse"}' >/dev/null || true
  PATH="$tr_shim:$PATH" CLAUDE_PLUGIN_DATA="$notice_data" \
    hook::notice_once "k-tr" '{"session_id":"s","hook_event_name":"PostToolUse"}' >/dev/null || true
  if [[ -s "$tr_log" ]]; then
    fail "notice_once spawned tr ($(wc -l <"$tr_log") times)"
  else
    ok "notice_once: reads the marker in-shell, does not exec tr"
  fi
  rm -rf "$notice_data"
  unset _HOOK_NOTICE_PRUNED
else
  fail "json_escape/notice_once tr pin: no real tr on PATH to wrap"
fi
rm -rf "$tr_shim"

hu_scratch="$(mktemp -d)"
hu_scratch_rc=0
TMPDIR="$hu_scratch" TMP="$hu_scratch" TEMP="$hu_scratch" \
  bash -c 'source "$1"; printf "{\"ok\":true}" | hook::buffer_stdin >/dev/null' \
  _ "$HOOK_DIR/hook-utils.sh" || hu_scratch_rc=$?
hu_left=$(find "$hu_scratch" -mindepth 1 2>/dev/null | wc -l | tr -cd '0-9')
if ((hu_scratch_rc == 0)) && [[ "${hu_left:-1}" == "0" ]]; then
  ok "buffer_stdin: isolated TMPDIR is empty after a successful read (no probe file)"
else
  fail "buffer_stdin leaked ${hu_left:-?} temp file(s) into TMPDIR (rc=$hu_scratch_rc)"
fi
rm -rf "$hu_scratch"

tr_shim="$(mktemp -d)"
tr_log="$tr_shim/log"
if make_logging_shim "$tr_shim" tr; then
  PATH="$tr_shim:$PATH" hook::repo_root /workspace >/dev/null
  if [[ -f "$tr_log" ]]; then
    fail "repo_root spawned tr ($(wc -l <"$tr_log") times)"
  else
    ok "repo_root: strips CR in-shell, does not exec tr"
  fi
else
  fail "repo_root tr pin: no real tr on PATH to wrap"
fi
rm -rf "$tr_shim"

corr_sink="$(mktemp)"
corr_payload='{"session_id":"sess-20","prompt_id":"p-20","tool_use_id":"toolu_01ABC","agent_id":"agent-7","cwd":"/x","tool_input":{"file_path":"a.md","content":"{\"session_id\":\"decoy\"}"}}'
INPUT="$corr_payload" HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"a.md","findings":[]}' 2>/dev/null
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  for pair in session_id=sess-20 prompt_id=p-20 tool_use_id=toolu_01ABC agent_id=agent-7; do
    key="${pair%%=*}" want="${pair#*=}"
    got=$(jq -r ".$key" "$corr_sink")
    if [[ "$got" == "$want" ]]; then ok "corr (builtin): $key copied from INPUT"; else fail "corr (builtin): $key expected $want, got $got"; fi
  done
  keys_order=$(jq -r 'keys_unsorted | join(",")' "$corr_sink")
  if [[ "$keys_order" == "schema_version,timestamp,hook,hook_event,status,duration_ms,session_id,prompt_id,tool_use_id,agent_id,data" ]]; then
    ok "corr (builtin): keys sit between duration_ms and data"
  else
    fail "corr (builtin): key order $keys_order"
  fi
  if [[ "$(jq -r '.data.session_id // "absent"' "$corr_sink")" == "absent" ]]; then ok "corr (builtin): data untouched"; else fail "corr (builtin): data gained a key"; fi
else
  fail "corr (builtin): sink empty"
  for key in session_id prompt_id tool_use_id agent_id; do
    fail "corr (builtin): $key not verifiable (no envelope)"
  done
  fail "corr (builtin): key order not verifiable (no envelope)"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
INPUT="$corr_payload" HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" $'{\n  "tool": "Write",\n  "file": "a.md",\n  "findings": []\n}' 2>/dev/null
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r '[.session_id, .prompt_id, .tool_use_id, .agent_id] | join(" ")' "$corr_sink")" == "sess-20 p-20 toolu_01ABC agent-7" ]]; then
    ok "corr (jq path): all four keys carried"
  else
    fail "corr (jq path): $(cat "$corr_sink")"
  fi
  if [[ "$(jq -r 'keys_unsorted | join(",")' "$corr_sink")" == "schema_version,timestamp,hook,hook_event,status,duration_ms,session_id,prompt_id,tool_use_id,agent_id,data" ]]; then
    ok "corr (jq path): same key order as the builtin path"
  else
    fail "corr (jq path): key order $(jq -r 'keys_unsorted | join(",")' "$corr_sink")"
  fi
else
  fail "corr (jq path): sink empty"
  fail "corr (jq path): key order not verifiable (no envelope)"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
INPUT='{"session_id":"../escape","prompt_id":"p 1","tool_use_id":"toolu_ok"}' HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"a.md","findings":[]}' 2>/dev/null
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r '[has("session_id"), has("prompt_id"), has("tool_use_id"), has("agent_id")] | join(" ")' "$corr_sink")" == "false false true false" ]]; then
    ok "corr: malformed ids dropped, well-formed one kept"
  else
    fail "corr: $(cat "$corr_sink")"
  fi
else
  fail "corr (partial): sink empty"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
INPUT='{"session_id":"sess-root","tool_input":{"options":{"prompt_id":"NESTED"}}}' HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write"}' 2>/dev/null
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r '[.session_id, (.prompt_id // "absent")] | join(" ")' "$corr_sink")" == "sess-root absent" ]]; then
    ok "corr: a nested prompt_id is not captured, the root session_id is"
  else
    fail "corr (nested key): $(cat "$corr_sink")"
  fi
else
  fail "corr (nested key): sink empty"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
INPUT='{"tool_input":{"n":{"session_id":"NESTED"}},"session_id":"sess-root"}' HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write"}' 2>/dev/null
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r '.session_id // "absent"' "$corr_sink")" == "sess-root" ]]; then
    ok "corr: the root session_id wins over one nested ahead of it"
  else
    fail "corr (nested first): $(cat "$corr_sink")"
  fi
else
  fail "corr (nested first): sink empty"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
INPUT='{"session_id":"s-1","prompt_id":"p-1","cwd":"/x","tool_name":"Bash","tool_input":{"command":"npm test","timeout":120000},"tool_response":{"ok":true},"tool_use_id":"toolu_1","agent_id":"a-1"}' HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write"}' 2>/dev/null
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r '[.session_id, .prompt_id, .tool_use_id, .agent_id] | join(" ")' "$corr_sink")" == "s-1 p-1 toolu_1 a-1" ]]; then
    ok "corr: all four ids captured with tool_use_id after tool_input"
  else
    fail "corr (documented order): $(cat "$corr_sink")"
  fi
else
  fail "corr (documented order): sink empty"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
INPUT='{"items":[{"session_id":"BAD"},{"agent_id":"BAD"}],"session_id":"good","agent_id":"ok"}' HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write"}' 2>/dev/null
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r '[.session_id, .agent_id] | join(" ")' "$corr_sink")" == "good ok" ]]; then
    ok "corr: decoys inside a root array are not reached"
  else
    fail "corr (array decoy): $(cat "$corr_sink")"
  fi
else
  fail "corr (array decoy): sink empty"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
(
  corr_big="$(head -c 1200000 /dev/zero | tr '\0' 'x')"
  INPUT='{"session_id":"s-big","prompt_id":"p-big","tool_input":{"content":"'"$corr_big"'","prompt_id":"NESTED"}}'
  HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
    hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write"}' 2>/dev/null
)
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r '[.session_id, .prompt_id] | join(" ")' "$corr_sink")" == "s-big p-big" ]]; then
    ok "corr: a multi-megabyte payload still yields the root ids"
  else
    fail "corr (large payload): $(jq -c '{session_id,prompt_id}' "$corr_sink")"
  fi
else
  fail "corr (large payload): sink empty"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
(
  corr_big="$(head -c 1200000 /dev/zero | tr '\0' 'x')"
  INPUT='{"session_id":"s-big","tool_input":{"content":"'"$corr_big"'","session_id":"NESTED"},"tool_use_id":"toolu_past_gate"}'
  HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
    hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write"}' 2>/dev/null
)
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r '[.session_id, (.tool_use_id // "omitted")] | join(" ")' "$corr_sink")" == "s-big omitted" ]]; then
    ok "corr: past the size gate the root id holds and no nested one is taken"
  else
    fail "corr (past gate): $(jq -c '{session_id,tool_use_id}' "$corr_sink")"
  fi
else
  fail "corr (past gate): sink empty"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
(
  unset INPUT HOOK_TELEMETRY_PAYLOAD
  HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
    hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"a.md","findings":[]}' 2>/dev/null
)
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ -s "$corr_sink" ]]; then
  if [[ "$(jq -r 'keys_unsorted | join(",")' "$corr_sink")" == "schema_version,timestamp,hook,hook_event,status,duration_ms,data" ]]; then
    ok "corr: no payload, no correlation keys"
  else
    fail "corr: unexpected keys without a payload: $(jq -r 'keys_unsorted | join(",")' "$corr_sink")"
  fi
else
  fail "corr (no payload): sink empty"
fi
rm -f "$corr_sink"
corr_sink="$(mktemp)"
INPUT='{"session_id":"from-input"}' HOOK_TELEMETRY_PAYLOAD='{"session_id":"from-payload"}' HOOK_TELEMETRY_SINK="$(make_sink "cat >\"$corr_sink\"")" \
  hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"a.md","findings":[]}' 2>/dev/null
wait_for_sink "$corr_sink" "$SINK_POLLS"
if [[ "$(jq -r '.session_id' "$corr_sink" 2>/dev/null)" == "from-payload" ]]; then
  ok "corr: HOOK_TELEMETRY_PAYLOAD overrides INPUT"
else
  fail "corr: override: $(cat "$corr_sink" 2>/dev/null)"
fi
rm -f "$corr_sink"

BG_WORK="$(mktemp -d)"
BG_DRIVER="$BG_WORK/begin-driver.sh"
cat >"$BG_DRIVER" <<'BGEOF'
#!/usr/bin/env bash
set -uo pipefail
# shellcheck disable=SC1090  # the suite passes the library path in
source "$BG_LIB"
# A stub reader makes the half of hook::begin that runs AFTER a path is
# admitted reachable for paths no test can create: a file directly under the
# filesystem root (needs privileges) and a spelling only Windows produces.
# hook::begin hands it the payload it already buffered, so no pipe feeds it.
if [[ -n "${BG_STUB_FILE:-}" ]]; then
  hook::read_file_path_to() { printf -v "$1" '%s' "$BG_STUB_FILE"; }
fi
# A host override, so one host checks the path splits of both platforms.
[[ -z "${BG_OSTYPE:-}" ]] || OSTYPE="$BG_OSTYPE"
# A repo-root resolver whose answer is NOT an ancestor of the file, which is
# what makes hook::repo_relative_path_to degrade to the basename.
bg_fake_root() { printf -v "$1" '%s' "${BG_ROOT_VALUE:-}"; }
hook::begin "$@"
printf 'REACHED=1\nFILE=%s\nBASE=%s\nDIR=%s\nROOT=%s\nTOOL=%s\nREL=%s\nDEGRADED=%s\nSTART=%s\n' \
  "$FILE" "$FILE_BASE" "$FILE_DIR" "$REPO_ROOT" "$TOOL" "$FILE_REL" "$FILE_REL_DEGRADED" \
  "$(if [[ -n "$start" ]]; then printf 1; else printf 0; fi)"
BGEOF
chmod +x "$BG_DRIVER"

bg_env=()
bg_run() {
  local bg_payload="$1"
  shift
  printf '%s' "$bg_payload" |
    env BG_LIB="$HOOK_DIR/hook-utils.sh" ${bg_env[@]+"${bg_env[@]}"} \
      bash "$BG_DRIVER" "$@" 2>&1
}
bg_field() {
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1
}
bg_payload() {
  printf '{"session_id":"bg-1","tool_name":"%s","tool_input":{"file_path":"%s"}}' \
    "${2:-Write}" "$1"
}

BG_REPO="$BG_WORK/consumer"
mkdir -p "$BG_REPO/sub"
(cd "$BG_REPO" && git init -q . && git config user.email t@e && git config user.name t) >/dev/null 2>&1
: >"$BG_REPO/sub/a.sh"
: >"$BG_REPO/sub/a.txt"
BG_OUTSIDE="$BG_WORK/outside"
mkdir -p "$BG_OUTSIDE"
: >"$BG_OUTSIDE/b.sh"

bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO")
bg_out=$(bg_run "$(bg_payload "$BG_REPO/sub/a.sh")" sample PostToolUse '*.sh')
bg_rc=$?
if ((bg_rc == 0)) && [[ "$(bg_field "$bg_out" REACHED)" == "1" &&
"$(bg_field "$bg_out" FILE)" == "$BG_REPO/sub/a.sh" &&
"$(bg_field "$bg_out" BASE)" == "a.sh" &&
"$(bg_field "$bg_out" DIR)" == "$BG_REPO/sub" &&
"$(bg_field "$bg_out" START)" == "1" ]]; then
  ok "begin: a matching edit yields FILE, FILE_BASE, FILE_DIR and a start stamp"
else
  fail "begin happy path (rc=$bg_rc): $bg_out"
fi
bg_want_root=$(git -C "$BG_REPO/sub" rev-parse --show-toplevel)
bg_want_root="${bg_want_root//$'\r'/}"
if [[ "$(bg_field "$bg_out" ROOT)" == "$bg_want_root" ]]; then
  ok "begin: REPO_ROOT is anchored at the file, not the process CWD"
else
  fail "begin repo root (rc=$bg_rc): $(bg_field "$bg_out" ROOT) want $bg_want_root; output: [$bg_out]"
fi

if [[ "$(bg_field "$bg_out" TOOL)" == "" &&
"$(bg_field "$bg_out" REL)" == "$BG_REPO/sub/a.sh" ]]; then
  ok "begin: sink unset → TOOL empty and FILE_REL unresolved"
else
  fail "begin sink unset (rc=$bg_rc): TOOL=$(bg_field "$bg_out" TOOL) REL=$(bg_field "$bg_out" REL); output: [$bg_out]"
fi
bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO" HOOK_TELEMETRY_SINK="$BG_WORK/sink-does-not-run")
bg_sink_out=$(bg_run "$(bg_payload "$BG_REPO/sub/a.sh" Edit)" sample PostToolUse '*.sh')
bg_sink_rc=$?
if [[ "$(bg_field "$bg_sink_out" TOOL)" == "Edit" &&
"$(bg_field "$bg_sink_out" REL)" == "sub/a.sh" &&
"$(bg_field "$bg_sink_out" DEGRADED)" == "0" ]]; then
  ok "begin: sink wired → TOOL parsed and FILE_REL made repo-relative"
else
  fail "begin sink wired (rc=$bg_sink_rc): [$bg_sink_out]"
fi

bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO" BG_ROOT_VALUE="$BG_WORK/elsewhere")
bg_deg_out=$(bg_run "$(bg_payload "$BG_REPO/sub/a.sh")" \
  --relative --repo-root bg_fake_root sample PostToolUse '*.sh')
bg_deg_rc=$?
if [[ "$(bg_field "$bg_deg_out" REL)" == "a.sh" &&
"$(bg_field "$bg_deg_out" DEGRADED)" == "1" ]]; then
  ok "begin: --relative with an unrelated root degrades FILE_REL and flags it"
else
  fail "begin degrade (rc=$bg_deg_rc): [$bg_deg_out]"
fi

while IFS='|' read -r bg_label bg_path bg_want_dir bg_want_base bg_row_host; do
  [[ -n "$bg_label" ]] || continue
  bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO" BG_STUB_FILE="$bg_path")
  case "$bg_row_host" in
  win) bg_env+=(BG_OSTYPE=msys) ;;
  posix) bg_env+=(BG_OSTYPE=linux-gnu) ;;
  *) ;;
  esac
  bg_row=$(bg_run "$(bg_payload "$BG_REPO/sub/a.sh")" sample PostToolUse)
  bg_row_rc=$?
  bg_got_dir="$(bg_field "$bg_row" DIR)"
  bg_got_base="$(bg_field "$bg_row" BASE)"
  if [[ "$bg_got_dir" == "$bg_want_dir" && "$bg_got_base" == "$bg_want_base" ]]; then
    ok "begin: $bg_label → FILE_DIR '$bg_got_dir', FILE_BASE '$bg_got_base'"
  else
    fail "begin: $bg_label → FILE_DIR '$bg_got_dir' (want '$bg_want_dir'), FILE_BASE '$bg_got_base' (want '$bg_want_base'), rc=$bg_row_rc, output: [$bg_row]"
  fi
done <<'BGTABLE'
a file under the filesystem root|/README.md|/|README.md|any
a bare relative name|README.md|.|README.md|any
a nested path|/a/b.md|/a|b.md|any
a deeper nested path|/a/b/c.md|/a/b|c.md|any
a file under a forward-slash drive root|C:/x.cs|C:/|x.cs|any
a forward-slash drive path|C:/a/b/x.cs|C:/a/b|x.cs|any
a Windows backslash path|C:\repo\x.md|C:\repo|x.md|win
a mixed-form path|/a/b\c.md|/a/b|c.md|win
a file under a backslash drive root|C:\x.cs|C:\|x.cs|win
a mixed path under a drive|C:/p\q\x.cs|C:/p\q|x.cs|win
a POSIX name holding a backslash|/a/b\c.md|/a|c.md|posix
BGTABLE
bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO")

bg_out=$(bg_run '{"session_id":"bg-2","tool_name":"Write","tool_input":{}}' sample PostToolUse '*.sh')
bg_rc=$?
if ((bg_rc == 0)) && [[ "$(bg_field "$bg_out" REACHED)" != "1" ]]; then
  ok "begin: no file_path → exit 0, no context"
else
  fail "begin no file_path (rc=$bg_rc): $bg_out"
fi

bg_out=$(bg_run "$(bg_payload "$BG_REPO/sub/a.txt")" sample PostToolUse '*.sh')
bg_rc=$?
if ((bg_rc == 0)) && [[ "$(bg_field "$bg_out" REACHED)" != "1" ]]; then
  ok "begin: a path no glob matches → exit 0, no context"
else
  fail "begin non-matching glob (rc=$bg_rc): $bg_out"
fi

bg_out=$(bg_run "$(bg_payload "$BG_OUTSIDE/b.sh")" sample PostToolUse '*.sh')
bg_rc=$?
if ((bg_rc == 0)) && [[ "$(bg_field "$bg_out" REACHED)" != "1" ]]; then
  ok "begin: a path outside CLAUDE_PROJECT_DIR → exit 0, no context"
else
  fail "begin out-of-project (rc=$bg_rc): $bg_out"
fi

bg_win_file='C:\repo\.github\workflows\ci.yml'                                                                               # portability-ok: literal backslash before the workflows segment of a path fixture, not a GNU grep \w character class
bg_win_payload='{"session_id":"bg-w","tool_name":"Write","tool_input":{"file_path":"C:\\repo\\.github\\workflows\\ci.yml"}}' # portability-ok: the same fixture path, backslash-escaped as the JSON literal carries it
bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO" BG_STUB_FILE="$bg_win_file")
bg_out=$(bg_run "$bg_win_payload" --no-membership sample PostToolUse '*/.github/workflows/*.yml')
bg_rc=$?
bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO")
if ((bg_rc == 0)) && [[ "$(bg_field "$bg_out" REACHED)" == "1" ]]; then
  ok "begin: an escaped Windows separator matches a glob naming an interior directory"
else
  fail "begin escaped separator (rc=$bg_rc): $bg_out"
fi

if command -v cygpath >/dev/null 2>&1; then
  bg_cwd_repo="$BG_WORK/cwd-repo"
  bg_file_repo="$BG_WORK/file-repo"
  mkdir -p "$bg_cwd_repo" "$bg_file_repo/tests/unit"
  git -C "$bg_cwd_repo" init -q . >/dev/null 2>&1
  git -C "$bg_file_repo" init -q . >/dev/null 2>&1
  : >"$bg_file_repo/tests/unit/x.cs"
  bg_want_root=$(git -C "$bg_file_repo" rev-parse --show-toplevel)
  bg_cwd_root=$(git -C "$bg_cwd_repo" rev-parse --show-toplevel)
  bg_bs_file=$(cygpath -w -- "$bg_file_repo/tests/unit/x.cs")
  bg_env=(CLAUDE_PROJECT_DIR="$bg_file_repo" BG_STUB_FILE="$bg_bs_file")
  bg_out=$(cd "$bg_cwd_repo" && bg_run "$(bg_payload "${bg_bs_file//\\/\\\\}")" --no-membership sample PostToolUse '*.cs')
  bg_rc=$?
  bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO")
  bg_got_root="$(bg_field "$bg_out" ROOT)"
  if ((bg_rc == 0)) && [[ -n "$bg_want_root" && "$bg_want_root" != "$bg_cwd_root" &&
    "$bg_got_root" == "$bg_want_root" ]]; then
    ok "begin: a backslash path resolves REPO_ROOT to the file's repository, not the CWD's"
  else
    fail "begin backslash REPO_ROOT (rc=$bg_rc): got '$bg_got_root', want '$bg_want_root', CWD repo '$bg_cwd_root', output: [$bg_out]"
  fi
else
  ok "begin: backslash REPO_ROOT SKIPPED (no cygpath — a backslash path names a directory only on Windows)"
fi

bg_out=$(bg_run '{"session_id":"bg-3","tool_input":{"file_path":"/x/a.sh"' sample PostToolUse '*.sh')
bg_rc=$?
if ((bg_rc == 0)) && [[ "$(bg_field "$bg_out" REACHED)" != "1" && "$bg_out" == *"cut short"* ]]; then
  ok "begin: stdin cut short mid-document (rc 3) → exit 0, no context"
else
  fail "begin cut-short stdin (rc=$bg_rc): $bg_out"
fi

BG_NOJQ="$(make_stub_bin)"
BG_DATA="$(mktemp -d)"
bg_run_nojq() {
  local bg_payload_txt="$1"
  shift
  printf '%s' "$bg_payload_txt" |
    BG_LIB="$HOOK_DIR/hook-utils.sh" PATH="$BG_NOJQ" HOOK_TELEMETRY_SINK="" \
      CLAUDE_PROJECT_DIR="$BG_REPO" CLAUDE_PLUGIN_DATA="$BG_DATA" \
      "$BASH" "$BG_DRIVER" "$@" 2>&1
}
bg_out=$(bg_run_nojq "$(bg_payload "$BG_REPO/sub/a.sh")" sample PostToolUse '*.sh')
bg_rc=$?
if ((bg_rc == 0)) && [[ "$bg_out" == *'"systemMessage"'* && "$(bg_field "$bg_out" REACHED)" != "1" ]]; then
  ok "begin: jq absent on a matching edit → the skip notice, then exit 0"
else
  fail "begin jq absent (rc=$bg_rc): $bg_out"
fi
rm -rf "$BG_DATA"
BG_DATA="$(mktemp -d)"
bg_out=$(bg_run_nojq "$(bg_payload "$BG_REPO/sub/a.txt")" sample PostToolUse '*.sh')
bg_rc=$?
if ((bg_rc == 0)) && [[ -z "$bg_out" ]]; then
  ok "begin: jq absent on a NON-matching edit → fully silent (pre-filter runs first)"
else
  fail "begin jq absent + non-matching glob (rc=$bg_rc): $bg_out"
fi
rm -rf "$BG_DATA" "$BG_NOJQ"

BG_SHIM="$(mktemp -d)"
if make_logging_shim "$BG_SHIM" jq; then
  bg_jq_count() {
    : >"$BG_SHIM/log"
    bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO" PATH="$BG_SHIM:$PATH")
    bg_run "$@" >/dev/null 2>&1
    local bg_n
    bg_n=$(grep -c . "$BG_SHIM/log" 2>/dev/null)
    printf '%s' "${bg_n:-0}"
  }
  bg_n_skip=$(bg_jq_count "$(bg_payload "$BG_REPO/sub/a.txt")" sample PostToolUse '*.sh')
  bg_n_run=$(bg_jq_count "$(bg_payload "$BG_REPO/sub/a.sh")" sample PostToolUse '*.sh')
  if ((bg_n_skip == 0)); then
    ok "begin: a non-matching edit spends no jq (payload validation is builtin)"
  else
    fail "begin: a non-matching edit spent $bg_n_skip jq processes, want 0"
  fi
  if ((bg_n_run <= bg_n_skip)); then
    ok "begin: an accepted edit with no sink spends no jq beyond that ($bg_n_run)"
  else
    fail "begin: an accepted edit with no sink spent $bg_n_run jq processes, ceiling $bg_n_skip"
  fi
  bg_env=(CLAUDE_PROJECT_DIR="$BG_REPO")
else
  fail "begin jq census: no real jq on PATH to wrap"
fi
rm -rf "$BG_SHIM"

dj=""
hook::data_json_to dj Write "sub/a.sh" "true" findings array '["x","y"]'
if [[ "$dj" == "$(jq -c -n '{tool:"Write",file:"sub/a.sh",findings:["x","y"],changed:true}')" ]]; then
  ok "data_json_to: {tool,file,findings} with changed:true"
else
  fail "data_json_to findings+changed: $dj"
fi
hook::data_json_to dj Write "sub/a.sh" "" findings array '[]'
if [[ "$dj" == "$(jq -c -n '{tool:"Write",file:"sub/a.sh",findings:[]}')" ]]; then
  ok "data_json_to: an empty verdict omits the changed key"
else
  fail "data_json_to changed omitted: $dj"
fi
hook::data_json_to dj Write "sub/a.md" "false" findings array '[]' applied array '["a"]'
if [[ "$dj" == "$(jq -c -n '{tool:"Write",file:"sub/a.md",findings:[],applied:["a"],changed:false}')" ]]; then
  ok "data_json_to: extra array keys keep their declared order"
else
  fail "data_json_to applied: $dj"
fi
hook::data_json_to dj Edit "sub/a.txt" "true" action str "crlf-to-lf"
if [[ "$dj" == "$(jq -c -n '{tool:"Edit",file:"sub/a.txt",action:"crlf-to-lf",changed:true}')" ]]; then
  ok "data_json_to: a str-typed key is emitted as a JSON string"
else
  fail "data_json_to action: $dj"
fi
hook::data_json_to dj Write 'a"b\c.sh' "" findings array '[]'
if [[ "$(printf '%s' "$dj" | jq -r '.file')" == 'a"b\c.sh' ]]; then
  ok "data_json_to: a quote and a backslash in the path round-trip"
else
  fail "data_json_to escaping: $dj"
fi
dj_big=$(jq -c -n '[range(4000) | "finding \(.) ................................"]')
hook::data_json_to dj Write "sub/a.sh" "" findings array "$dj_big"
if [[ "$(printf '%s' "$dj" | jq -r '.findings | length')" == "4000" ]]; then
  ok "data_json_to: a ${#dj_big}-character findings array survives (stdin, not argv)"
else
  fail "data_json_to large array: $(printf '%s' "$dj" | head -c 200)"
fi

# --- hook::path_matches ------------------------------------------------------
pm_win='C:\r\.github\workflows\ci.yml' # portability-ok: a quoted path literal, not a regex; \w opens `workflows`
if hook::path_matches "/r/x.sh" '*.py' '*.sh' &&
  ! hook::path_matches "/r/x.txt" '*.py' '*.sh' &&
  hook::path_matches "$pm_win" '*/.github/workflows/*.yml' &&
  ! hook::path_matches "/r/.github/actions/ci.yml" '*/.github/workflows/*.yml'; then
  ok "path_matches: extension and path globs, on either separator"
else
  fail "path_matches: one of the four cases disagreed"
fi
if ! hook::path_matches "/r/x.sh"; then
  ok "path_matches: no globs matches nothing (the caller checks for that first)"
else
  fail "path_matches: an empty glob list matched"
fi

rm -rf "$BG_WORK"

hook::ctx_reset
hook::ctx_append "first line"
hook::ctx_append "  second line"
cf_flush=$(
  hook::ctx_flush PostToolUse
  printf X
)
cf_direct=$(
  hook::emit_channels PostToolUse "first line"$'\n'"  second line" ""
  printf X
)
if [[ "$cf_flush" == "$cf_direct" ]]; then
  ok "ctx_flush: byte-identical to emit_channels for the same context"
else
  fail "ctx_flush: [$cf_flush] != emit_channels [$cf_direct]"
fi
hook::ctx_reset
cf_empty=$(
  hook::ctx_flush PostToolUse
  printf X
)
if [[ "$cf_empty" == "X" ]]; then
  ok "ctx_flush: an empty buffer emits nothing, as emit_channels does"
else
  fail "ctx_flush empty buffer: [$cf_empty]"
fi

cf_shim="$(mktemp -d)"
cf_log="$cf_shim/log"
if make_logging_shim "$cf_shim" jq; then
  hook::ctx_reset
  hook::ctx_append "census line"
  PATH="$cf_shim:$PATH" hook::ctx_flush PostToolUse >/dev/null
  if [[ -f "$cf_log" ]]; then
    fail "ctx_flush spawned jq ($(grep -c . "$cf_log") times)"
  else
    ok "ctx_flush: builds the document in-shell, spawns no jq"
  fi
else
  fail "ctx_flush jq census: no real jq on PATH to wrap"
fi
rm -rf "$cf_shim"

FIN_WORK="$(mktemp -d)"
# shellcheck disable=SC2016  # the child shell's own program text: $1..$4 are ITS positional parameters
FIN_PROG='
set -uo pipefail
source "$1"
source "$2"
start="${EPOCHREALTIME:-}"
TOOL=Write
FILE_REL="a.txt"
REPO_ROOT=""
HOOK_PLUGIN=fixture
HOOK_EVENT=PostToolUse
fin_target="$3"
fin_mode="$4"
shift 4
case "$fin_mode" in
armed) hook::rewrite_guard_begin "$fin_target" ;;
rewrote)
  hook::rewrite_guard_begin "$fin_target"
  printf "rewritten by the tool\n" >"$fin_target"
  ;;
unarmed) : ;;
esac
hook::finish "$@"
printf "REACHED PAST FINISH\n"
'

fin_rc=0
fin_leaked=0
fin_out=""
fin_arm() {
  local mode="$1" sink="$2" tel="$3"
  shift 3
  local scratch="$FIN_WORK/scratch.$RANDOM"
  local target="$FIN_WORK/target.$RANDOM"
  mkdir -p "$scratch"
  printf 'original\n' >"$target"
  fin_out=$(
    TMPDIR="$scratch" TMP="$scratch" TEMP="$scratch" HOOK_TELEMETRY_SINK="$sink" \
      bash -c "$FIN_PROG" _ "$HOOK_DIR/hook-utils.sh" "$HOOK_DIR/rewrite-guard.sh" \
      "$target" "$mode" "$@"
  )
  fin_rc=$?
  local waited=0
  while [[ ! -s "$tel" ]] && ((waited < 150)); do
    sleep 0.1
    waited=$((waited + 1))
  done
  fin_leaked=$(find "$scratch" -mindepth 1 2>/dev/null | wc -l | tr -cd '0-9')
  rm -rf "$scratch" "$target"
}

fin_check() {
  local label="$1" want_docs="$2" want_changed="$3" tel="$4"
  local out="$fin_out" docs=0
  [[ -n "$out" ]] && docs=$(printf '%s\n' "$out" | grep -c .)
  if ((fin_rc == 0)); then
    ok "finish/$label: exit 0"
  else
    fail "finish/$label: exit $fin_rc"
  fi
  if ((docs == want_docs)) && { ((docs == 0)) || printf '%s' "$out" | jq -e . >/dev/null 2>&1; }; then
    ok "finish/$label: exactly $want_docs JSON document(s) on stdout"
  else
    fail "finish/$label: $docs document(s), want $want_docs: $out"
  fi
  local got_changed
  got_changed=$(jq -r 'if (.data | has("changed")) then (.data.changed | tostring) else "absent" end' "$tel" 2>/dev/null) ||
    got_changed="unreadable"
  if [[ "$got_changed" == "$want_changed" ]]; then
    ok "finish/$label: data.changed $want_changed"
  elif [[ ! -s "$tel" ]]; then
    fail "finish/$label: data.changed not verifiable, no envelope arrived within fin_arm's 15 s poll (want $want_changed)"
  else
    fail "finish/$label: data.changed $got_changed, want $want_changed"
  fi
  if [[ "${fin_leaked:-1}" == "0" ]]; then
    ok "finish/$label: snapshot released (isolated TMPDIR empty)"
  else
    fail "finish/$label: leaked ${fin_leaked:-?} snapshot file(s)"
  fi
}

fin_tel="$FIN_WORK/tel.json"
fin_sink="$(make_sink "cat >\"$fin_tel\"")"

: >"$fin_tel"
fin_arm armed "$fin_sink" "$fin_tel" --disclose "fixture: reformatted a.txt." ok findings array '[]'
fin_check clean 0 false "$fin_tel"

: >"$fin_tel"
fin_arm rewrote "$fin_sink" "$fin_tel" --disclose "fixture: reformatted a.txt." ok findings array '[]'
fin_check clean-rewrote 1 true "$fin_tel"
if [[ "$(printf '%s' "$fin_out" | jq -r '.systemMessage // empty')" == "fixture: reformatted a.txt." ]] &&
  [[ -z "$(printf '%s' "$fin_out" | jq -r '.hookSpecificOutput.additionalContext // empty')" ]]; then
  ok "finish/clean-rewrote: disclosure on the user channel alone"
else
  fail "finish/clean-rewrote: $fin_out"
fi

: >"$fin_tel"
fin_arm rewrote "$fin_sink" "$fin_tel" --context "fixture: a.txt has findings:" \
  --disclose "fixture: reformatted a.txt." ok findings array '["one","two"]'
fin_check findings 1 true "$fin_tel"
if [[ "$(printf '%s' "$fin_out" | jq -r '.hookSpecificOutput.additionalContext // empty')" == "fixture: a.txt has findings:" ]] &&
  [[ "$(printf '%s' "$fin_out" | jq -r '.systemMessage // empty')" == "fixture: reformatted a.txt." ]] &&
  [[ "$(jq -c '.data.findings' "$fin_tel" 2>/dev/null)" == '["one","two"]' ]]; then
  ok "finish/findings: both channels in one document, findings on the envelope"
else
  fail "finish/findings: $fin_out / $(jq -c '.data.findings' "$fin_tel" 2>/dev/null)"
fi

: >"$fin_tel"
fin_arm armed "$fin_sink" "$fin_tel" --disclose "fixture: reformatted a.txt." skipped findings array '[]'
fin_check consumer-ignored 0 false "$fin_tel"
if [[ "$(jq -r '.status' "$fin_tel" 2>/dev/null)" == "skipped" ]]; then
  ok "finish/consumer-ignored: status skipped"
else
  fail "finish/consumer-ignored: status $(jq -r '.status' "$fin_tel" 2>/dev/null)"
fi

: >"$fin_tel"
fin_arm rewrote "$fin_sink" "$fin_tel" --context "fixture: the tool broke:" \
  --disclose "fixture: reformatted a.txt." skipped findings array '[]'
fin_check tool-break 1 true "$fin_tel"
if [[ "$(printf '%s' "$fin_out" | jq -r '.systemMessage // empty')" == "fixture: reformatted a.txt." ]] &&
  [[ "$(jq -r '.status' "$fin_tel" 2>/dev/null)" == "skipped" ]]; then
  ok "finish/tool-break: disclosure survives the break, status skipped"
else
  fail "finish/tool-break: $fin_out / $(jq -r '.status' "$fin_tel" 2>/dev/null)"
fi

: >"$fin_tel"
fin_arm unarmed "$fin_sink" "$fin_tel" skipped findings array '[]'
fin_check skipped 0 false "$fin_tel"

: >"$fin_tel"
fin_arm armed "$fin_sink" "$fin_tel" --changed true ok findings array '[]'
fin_check changed-override 0 true "$fin_tel"
: >"$fin_tel"
fin_arm unarmed "$fin_sink" "$fin_tel" --changed "" ok findings array '[]'
fin_check changed-unknown 0 absent "$fin_tel"

: >"$fin_tel"
fin_arm rewrote "$fin_sink" "$fin_tel" --context "ctx" --message "notice text" \
  --disclose "fixture: reformatted a.txt." ok findings array '[]'
fin_msg=$(printf '%s' "$fin_out" | jq -r '.systemMessage // empty')
fin_msg="${fin_msg//$'\r'/}"
if [[ "$fin_msg" == "fixture: reformatted a.txt."$'\n'"notice text" ]]; then
  ok "finish: the caller's message follows the disclosure on the user channel"
else
  fail "finish message compose: $(printf '%s' "$fin_out" | jq -c '.systemMessage')"
fi

: >"$fin_tel"
fin_arm unarmed "$fin_sink" "$fin_tel" --id other-id ok findings array '[]'
if [[ "$(jq -r '.hook' "$fin_tel" 2>/dev/null)" == "other-id" ]]; then
  ok "finish: --id overrides HOOK_PLUGIN as the telemetry hook id"
else
  fail "finish --id: hook_id $(jq -r '.hook' "$fin_tel" 2>/dev/null)"
fi

rm -f "$fin_sink"
rm -rf "$FIN_WORK"

WU_WORK="$(mktemp -d)"
mkdir -p "$WU_WORK/repo/a/b/c"
: >"$WU_WORK/repo/MARK"
: >"$WU_WORK/repo/a/MARK"
: >"$WU_WORK/MARK" # above the ceiling: never a legitimate answer

wu_calls=""
wu_mark_here() {
  wu_calls+="$1"$'\n'
  [[ -f "$1/MARK" ]]
}
wu_never() {
  wu_calls+="$1"$'\n'
  return 1
}
wu_stop_at_b() {
  wu_calls+="$1"$'\n'
  [[ "${1##*/}" == "b" ]] && return 2
  [[ -f "$1/MARK" ]]
}

wu_case() {
  local label="$1" start="$2" ceiling="$3" pred="$4" mode="$5" want="$6" want_rc="$7"
  wu_calls=""
  local got=""
  hook::walk_up_to got "$start" "$ceiling" "$pred" "$mode"
  local rc=$?
  if [[ "$got" == "$want" ]] && ((rc == want_rc)); then
    ok "walk_up_to/$label: $got (rc $rc)"
  else
    fail "walk_up_to/$label: got '$got' rc $rc, want '$want' rc $want_rc (visited: ${wu_calls//$'\n'/ })"
  fi
}

wu_case "first hit" "$WU_WORK/repo/a/b/c" "$WU_WORK/repo" wu_mark_here first "$WU_WORK/repo/a" 0
wu_case "topmost hit" "$WU_WORK/repo/a/b/c" "$WU_WORK/repo" wu_mark_here topmost "$WU_WORK/repo" 0
wu_case "default mode is first" "$WU_WORK/repo/a/b/c" "$WU_WORK/repo" wu_mark_here "" "$WU_WORK/repo/a" 0
wu_case "stops at the ceiling" "$WU_WORK/repo/a/b/c" "$WU_WORK/repo/a/b" wu_mark_here first "" 1
wu_case "predicate rc 2 stops without accepting" "$WU_WORK/repo/a/b/c" "$WU_WORK/repo" wu_stop_at_b first "" 1
wu_case "unresolvable ceiling fails closed" "$WU_WORK/repo/a/b/c" "" wu_mark_here first "" 1
wu_case "empty start fails closed" "" "$WU_WORK/repo" wu_mark_here first "" 1

wu_calls=""
# shellcheck disable=SC2034  # these rows assert which directories the walk visited, not its destination
wu_hit=""
hook::walk_up_to wu_hit "$WU_WORK/repo/a/b/c" "$WU_WORK/repo" wu_never first
if [[ "$wu_calls" != *"$WU_WORK"$'\n'* ]] && [[ "$wu_calls" == *"$WU_WORK/repo"$'\n'* ]]; then
  ok "walk_up_to: the ceiling directory is visited and its parent is not"
else
  fail "walk_up_to ceiling bound: visited ${wu_calls//$'\n'/ }"
fi

wu_calls=""
# shellcheck disable=SC2034  # these rows assert which directories the walk visited, not its destination
wu_hit=""
hook::walk_up_to wu_hit "$WU_WORK/repo/a" "" wu_never first
if [[ -z "$wu_calls" ]]; then
  ok "walk_up_to: an unresolvable ceiling walks nowhere, asking nothing"
else
  fail "walk_up_to unresolvable ceiling asked: ${wu_calls//$'\n'/ }"
fi

wu_calls=""
# shellcheck disable=SC2034  # these rows assert which directories the walk visited, not its destination
wu_hit=""
hook::walk_up_to wu_hit / / wu_never first
if [[ "$wu_calls" == "/"$'\n' ]]; then
  ok "walk_up_to: a start of / asks exactly once and stops"
else
  fail "walk_up_to start /: visited ${wu_calls//$'\n'/ }"
fi

wu_calls=""
# shellcheck disable=SC2034  # these rows assert which directories the walk visited, not its destination
wu_hit=""
hook::walk_up_to wu_hit . "$WU_WORK/repo" wu_never first
if [[ "$wu_calls" == "."$'\n' ]]; then
  ok "walk_up_to: a start of . asks exactly once and stops"
else
  fail "walk_up_to start .: visited ${wu_calls//$'\n'/ }"
fi

wu_calls=""
# shellcheck disable=SC2034  # these rows assert which directories the walk visited, not its destination
wu_hit=""
hook::walk_up_to wu_hit "$WU_WORK/repo/a/b/c" / wu_never first
if [[ "$wu_calls" == *$'\n'"/"$'\n' ]]; then
  ok "walk_up_to: a / ceiling walks to the filesystem root and stops there"
else
  fail "walk_up_to filesystem root: visited ${wu_calls//$'\n'/ }"
fi

rm -rf "$WU_WORK"

FF_FILTERS=('.tool_input.command' '.tool_name' '.cwd' '.tool_input.file_path' '.tool_input.content' '.hook_event_name')
fast_fields_is_jq() { # <desc> <payload>
  local desc="$1" payload="$2" rc=0 src=0 i same=1
  local -a fast=() slow=()
  hook::_fast_fields "$payload" "${FF_FILTERS[@]}" || rc=$?
  if ((rc == 2)); then
    ok "fast fields: $desc (falls back to jq)"
    return
  fi
  if ((rc != 0)); then
    fail "fast fields ($desc): rc=$rc"
    return
  fi
  fast=("${HOOK_JQ_FIELDS[@]}")
  local fnul=$HOOK_JQ_FIELDS_NUL
  mapfile -d '' slow < <(
    hook::_fast_fields() { return 2; }
    hook::jq_fields_uncached "$payload" "${FF_FILTERS[@]}" || exit $?
    printf '%s\0' "$HOOK_JQ_FIELDS_NUL" "${HOOK_JQ_FIELDS[@]}"
  ) || src=$?
  if ((src != 0)); then
    fail "fast fields ($desc): proven by the fast path but the jq path returned $src"
    return
  fi
  [[ "${slow[0]}" == "$fnul" ]] || same=0
  ((${#slow[@]} - 1 == ${#fast[@]})) || same=0
  for ((i = 0; i < ${#fast[@]}; i++)); do
    [[ "${fast[i]}" == "${slow[i + 1]-}" ]] || same=0
  done
  if ((same)); then
    ok "fast fields: $desc (proven)"
  else
    fail "fast fields ($desc): fast [$(printf '%q ' "${fast[@]}")] jq [$(printf '%q ' "${slow[@]:1}")]"
  fi
}
fast_fields_is_jq "Bash payload" '{"session_id":"s","cwd":"C:\\code\\proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"true","description":"probe"}}'
# shellcheck disable=SC2016  # the $_ is PowerShell's, inside a JSON payload
fast_fields_is_jq "PowerShell payload with braces and backslashes" '{"tool_name":"PowerShell","cwd":"C:\\Dev","tool_input":{"command":"Get-ChildItem C:\\Dev | Where-Object { $_.Name -like \"*x*\" }"}}'
fast_fields_is_jq "escapes in the command" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"a\\nb\" && echo \"\\t\"\\\\x"}}'
fast_fields_is_jq "CR inside a value is stripped like jq's output" '{"tool_name":"Bash","tool_input":{"command":"a\r\nb"}}'
fast_fields_is_jq "number and boolean siblings" '{"tool_name":"Bash","tool_input":{"command":"ls","timeout":600000,"run_in_background":true}}'
fast_fields_is_jq "empty tool_input" '{"tool_name":"Bash","tool_input":{}}'
fast_fields_is_jq "no tool_input" '{"tool_name":"Bash"}'
fast_fields_is_jq "null tool_input" '{"tool_name":"Bash","tool_input":null}'
fast_fields_is_jq "null command" '{"tool_name":"Bash","tool_input":{"command":null}}'
fast_fields_is_jq "empty command" '{"tool_name":"Bash","tool_input":{"command":""}}'
fast_fields_is_jq "Write payload" '{"tool_name":"Write","tool_input":{"file_path":"C:\\repo\\a.md","content":"line1\nline2 {\"x\":[1]}"}}'
fast_fields_is_jq "pretty-printed payload" "$(jq -n '{tool_name:"Bash",cwd:"/x",tool_input:{command:"git status"}}')"
fast_fields_is_jq "keys spelled with unicode escapes" '{"tool\u005fname":"Bash","tool_input":{"comm\u0061nd":"x"}}'
fast_fields_is_jq "non-ASCII value" '{"tool_name":"Bash","tool_input":{"command":"echo é 日本"}}'
fast_fields_is_jq "tool_input is a string" '{"tool_name":"Bash","tool_input":"x"}'
fast_fields_is_jq "nested object inside tool_input" '{"tool_name":"Bash","tool_input":{"command":"ls","meta":{"a":1}}}'
fast_fields_is_jq "key spelled as a value elsewhere" '{"tool_name":"command","tool_input":{"command":"ls"}}'
fast_fields_is_jq "duplicate key" '{"tool_name":"Bash","tool_input":{"command":"a","command":"b"}}'
fast_fields_is_jq "same key at the root and inside" '{"command":"root","tool_name":"Bash","tool_input":{"command":"in"}}'
fast_fields_is_jq "non-ASCII unicode escape" '{"tool_name":"Bash","tool_input":{"command":"\u00e9"}}'
fast_fields_is_jq "NUL escape" '{"tool_name":"Bash","tool_input":{"command":"a\u0000b"}}'
fast_fields_is_jq "number tool_name" '{"tool_name":5,"tool_input":{"command":"x"}}'
fast_fields_is_jq "false command" '{"tool_name":"Bash","tool_input":{"command":false}}'
fast_fields_is_jq "truncated payload" '{"tool_name":"Bash","tool_input":{"command":"x"'
fast_fields_is_jq "array root" '[{"tool_name":"Bash"}]'
for ff_case in '{"tool_name":"Bash","tool_input":{"command":"a\u0000b"}}' \
  '{"tool_name":"Bash","tool_input":{"command":"a","command":"b"}}' \
  '{"tool_name":"Bash","tool_input":{"command":7}}' \
  '{"tool_name":"Bash","tool_input":"x"}'; do
  ff_rc=0
  hook::_fast_fields "$ff_case" '.tool_input.command' || ff_rc=$?
  if ((ff_rc == 2)); then
    ok "fast fields: not proven, jq runs: ${ff_case:19:40}"
  else
    fail "fast fields: rc=$ff_rc on a shape only jq may answer: $ff_case"
  fi
done
ff_rc=0
hook::_fast_fields '{"tool_input":{"files":[1,2]}}' '.tool_input.files | length' || ff_rc=$?
if ((ff_rc == 2)); then ok "fast fields: a non-path filter falls back to jq"; else fail "fast fields: non-path filter rc=$ff_rc"; fi
hook::_fast_fields '{"tool_name":"Bash","tool_input":{"command":"ls"}}' '.cwd' '.tool_input.file_path' '.tool_input.command'
if [[ "${HOOK_JQ_FIELDS[0]}" == "" && "${HOOK_JQ_FIELDS[1]}" == "" && "${HOOK_JQ_FIELDS[2]}" == "ls" ]]; then
  ok "fast fields: absent keys are proven empty beside a present one"
else
  fail "fast fields: absent keys: [$(printf '%q ' "${HOOK_JQ_FIELDS[@]}")]"
fi
hook::jq_fields '{"tool_name":"Bash","tool_input":{"command":"true"}}' '.tool_input.command' '.tool_name'
if [[ "${HOOK_JQ_FIELDS[0]}" == "true" && "${HOOK_JQ_FIELDS[1]}" == "Bash" && "$HOOK_JQ_FIELDS_NUL" == 0 ]]; then
  ok "jq_fields: the common Bash payload is answered"
else
  fail "jq_fields common payload: [$(printf '%q ' "${HOOK_JQ_FIELDS[@]}")] nul=$HOOK_JQ_FIELDS_NUL"
fi

ff_pair_check() { # <desc> <payload> <filter> <expected>
  local desc="$1" payload="$2" filter="$3" want="$4" rc=0 src=0 slow
  hook::_fast_fields "$payload" "$filter" || rc=$?
  if ((rc != 0)); then
    fail "$desc: the fast path did not prove it (rc=$rc)"
    return
  fi
  slow=$(
    hook::_fast_fields() { return 2; }
    hook::jq_fields_uncached "$payload" "$filter" || exit $?
    printf '%s' "${HOOK_JQ_FIELDS[0]}"
  ) || src=$?
  if ((src != 0)); then
    fail "$desc: proven by the fast path but the jq path returned $src"
    return
  fi
  if [[ "${HOOK_JQ_FIELDS[0]}" == "$want" && "$slow" == "$want" ]]; then
    ok "$desc"
  else
    fail "$desc: fast=[${HOOK_JQ_FIELDS[0]}] jq=[$slow] want=[$want]"
  fi
}
ff_long=""
ff_gone=""
for ((ff_i = 0; ff_i < 70; ff_i++)); do
  ff_long+=k
  ff_gone+=z
done
ff_pair_check "fast fields: a present key name longer than 60 characters is not skipped" \
  "{\"$ff_long\":\"present\",\"tool_name\":\"Bash\"}" ".$ff_long" "present"
ff_pair_check "fast fields: a key name longer than 60 characters that is absent is proven empty" \
  "{\"$ff_long\":\"present\",\"tool_name\":\"Bash\"}" ".$ff_gone" ""
ff_esc=""
ff_name=hook_event_name
for ((ff_i = 0; ff_i < ${#ff_name}; ff_i++)); do
  printf -v ff_ch '\\u%04x' "'${ff_name:ff_i:1}"
  ff_esc+=$ff_ch
done
ff_pair_check "fast fields: a key spelled entirely with \\u escapes is recognized" \
  "{\"$ff_esc\":\"PreToolUse\",\"tool_name\":\"Bash\"}" ".$ff_name" "PreToolUse"
ff_ra='.tool_input.replace_all // false | tostring'
ff_pair_check "fast fields: // false | tostring on false" '{"tool_input":{"replace_all":false}}' "$ff_ra" "false"
ff_pair_check "fast fields: // false | tostring on true" '{"tool_input":{"replace_all":true}}' "$ff_ra" "true"
ff_pair_check "fast fields: // false | tostring on an absent key" '{"tool_input":{"new_string":"x"}}' "$ff_ra" "false"
ff_pair_check "fast fields: // false | tostring on a null parent" '{"tool_input":null}' "$ff_ra" "false"
ff_pair_check "fast fields: // false | tostring on an empty string" '{"tool_input":{"replace_all":""}}' "$ff_ra" ""
ff_pair_check "fast fields: // false | tostring at the root" '{"replace_all":true}' '.replace_all // false | tostring' "true"
ff_rc=0
hook::_fast_fields '{"tool_input":{"replace_all":1}}' "$ff_ra" || ff_rc=$?
if ((ff_rc == 2)); then ok "fast fields: // false | tostring on a number falls back to jq"; else fail "fast fields: number rc=$ff_rc"; fi
ff_rc=0
hook::_fast_fields '{"tool_input":{"replace_all":true}}' '.tool_input.replace_all' || ff_rc=$?
if ((ff_rc == 2)); then ok "fast fields: a bare boolean read still falls back to jq"; else fail "fast fields: bare boolean rc=$ff_rc"; fi

ff_floor_payload='{"session_id":"s","cwd":"/x","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"true","file_path":"/a b","content":"c\nd"}}'
ff_floor_rc=0
ff_floor=()
mapfile -d '' ff_floor < <(
  hook::_fast_fields_supported() { return 1; }
  hook::_fast_fields() {
    printf 'FAST-PATH-RAN-BELOW-FLOOR\0'
    builtin exit 99
  }
  hook::jq_fields "$ff_floor_payload" "${FF_FILTERS[@]}" || exit $?
  printf '%s\0' "$HOOK_JQ_FIELDS_NUL" "${HOOK_JQ_FIELDS[@]}"
)
hook::jq_fields "$ff_floor_payload" "${FF_FILTERS[@]}" || ff_floor_rc=$?
ff_same=1
((ff_floor_rc == 0)) || ff_same=0
((${#ff_floor[@]} == ${#FF_FILTERS[@]} + 1)) || ff_same=0
[[ "${ff_floor[0]-}" == "$HOOK_JQ_FIELDS_NUL" ]] || ff_same=0
for ((ff_i = 0; ff_i < ${#HOOK_JQ_FIELDS[@]}; ff_i++)); do
  [[ "${ff_floor[ff_i + 1]-}" == "${HOOK_JQ_FIELDS[ff_i]}" ]] || ff_same=0
done
if ((ff_same)); then
  ok "jq_fields: below the Bash 4.0 floor the fast path is skipped and jq answers the same"
else
  fail "jq_fields below the floor: got [$(printf '%q ' "${ff_floor[@]}")] want nul=$HOOK_JQ_FIELDS_NUL [$(printf '%q ' "${HOOK_JQ_FIELDS[@]}")]"
fi
unset ff_case ff_rc ff_long ff_gone ff_esc ff_name ff_ch ff_i ff_same ff_floor ff_floor_rc ff_floor_payload
unset -f ff_pair_check

ed_out=$(hook::emit_channels PreToolUse "ctx" "sys")
ed_doc=$(hook::emit_document '{"a":1}')
if [[ "$ed_out" == '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"ctx"},"systemMessage":"sys"}' && "$ed_doc" == '{"a":1}' ]]; then
  ok "emit_document prints one document with a trailing newline, and emit_channels goes through it"
else
  fail "emit_document: channels=[$ed_out] doc=[$ed_doc]"
fi
ed_seen=$(
  hook::emit_document() { printf '<%s>' "$1"; }
  hook::emit_channels PostToolUse "c1" ""
  hook::emit_channels PostToolUse "" "s2"
)
if [[ "$ed_seen" == '<{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"c1"}}><{"systemMessage":"s2"}>' ]]; then
  ok "an override of emit_document collects every document emit_channels builds"
else
  fail "emit_document override saw: $ed_seen"
fi
unset ed_out ed_doc ed_seen

for es_case in 'Bash|git status' 'Bash|sudo git push' 'Bash|FOO=1 make all' 'Bash|TOKEN="a b" curl x' 'Bash|TOKEN=secret' 'Bash|/usr/bin/env' 'Bash|' 'PowerShell|git status' 'Write|'; do
  es_tool="${es_case%%|*}"
  es_cmd="${es_case#*|}"
  es_to=""
  hook::extract_bash_subject_to es_to "$es_tool" "$es_cmd"
  es_print=$(hook::extract_bash_subject "$es_tool" "$es_cmd")
  if [[ "$es_to" == "$es_print" ]]; then
    ok "extract_bash_subject_to matches the print form: $es_case -> $es_to"
  else
    fail "extract_bash_subject_to [$es_to] vs print form [$es_print] for $es_case"
  fi
done
es_to=""
hook::extract_bash_subject_to es_to Bash 'TOKEN="a b" curl x'
if [[ "$es_to" == Bash ]]; then ok "subject: a quoted assignment value never reaches the subject"; else fail "subject leaked: $es_to"; fi
unset es_case es_tool es_cmd es_to es_print

if command -v git >/dev/null 2>&1; then
  GI_ROOT="$(mktemp -d)"
  GREPO="$GI_ROOT/grepo"
  mkdir -p "$GREPO/.work" "$GREPO/src"
  git -C "$GREPO" init -q
  git -C "$GREPO" config core.excludesFile /dev/null
  git -C "$GREPO" config user.email t@t.t
  git -C "$GREPO" config user.name t
  printf '.work/\n*.gen.sh\n' >"$GREPO/.gitignore"
  printf 'x\n' >"$GREPO/.work/scratch.sh"
  printf 'x\n' >"$GREPO/src/plain.sh"
  printf 'x\n' >"$GREPO/src/tracked.gen.sh"
  git -C "$GREPO" add -f src/tracked.gen.sh
  git -C "$GREPO" commit -q -m init

  if hook::file_is_gitignored "$GREPO/.work/scratch.sh"; then
    ok "gitignored: an ignored untracked file reads as ignored"
  else
    fail "gitignored: .work/scratch.sh did not read as ignored"
  fi
  if ! hook::file_is_gitignored "$GREPO/src/tracked.gen.sh"; then
    ok "gitignored: a tracked file matching an ignore pattern reads as not ignored"
  else
    fail "gitignored: a tracked file read as ignored"
  fi
  if ! hook::file_is_gitignored "$GREPO/src/plain.sh"; then
    ok "gitignored: an ordinary file reads as not ignored"
  else
    fail "gitignored: src/plain.sh read as ignored"
  fi

  NOREPO="$GI_ROOT/norepo"
  mkdir -p "$NOREPO"
  printf 'x\n' >"$NOREPO/loose.sh"
  if ! hook::file_is_gitignored "$NOREPO/loose.sh"; then
    ok "gitignored: a file in no repository reads as not ignored"
  else
    fail "gitignored: a file in no repository read as ignored"
  fi
  if ! hook::file_is_gitignored "$GI_ROOT/missing-dir/gone.sh"; then
    ok "gitignored: a vanished directory fails toward acting (not ignored)"
  else
    fail "gitignored: a vanished directory read as ignored"
  fi

  OTHER="$GI_ROOT/other"
  mkdir -p "$OTHER"
  git -C "$OTHER" init -q
  if (GIT_DIR="$OTHER/.git" GIT_WORK_TREE="$OTHER" hook::file_is_gitignored "$GREPO/.work/scratch.sh"); then
    ok "gitignored: an inherited GIT_DIR/GIT_WORK_TREE is cleared (still ignored)"
  else
    fail "gitignored: an inherited GIT_DIR/GIT_WORK_TREE decided the answer"
  fi

  FSM="$GI_ROOT/fsm"
  git -C "$GI_ROOT" clone -q "$GREPO" "$FSM" 2>/dev/null
  printf '.work/\n' >"$FSM/.gitignore"
  mkdir -p "$FSM/.work"
  printf '#!/bin/sh\ntouch "%s"\n' "$GI_ROOT/fsm-ran" >"$GI_ROOT/fsm.sh"
  chmod +x "$GI_ROOT/fsm.sh"
  FSM_HOOK="$GI_ROOT/fsm.sh"
  command -v cygpath >/dev/null 2>&1 && FSM_HOOK=$(cygpath -m "$FSM_HOOK")
  printf '[core]\n\tfsmonitor = %s\n' "$FSM_HOOK" >"$GI_ROOT/fsm-include"
  git -C "$FSM" config core.fsmonitor "$GI_ROOT/fsm.sh"
  git -C "$FSM" config include.path "$GI_ROOT/fsm-include"
  if hook::file_is_gitignored "$FSM/.work/x.sh" && [[ ! -e "$GI_ROOT/fsm-ran" ]]; then
    ok "gitignored: a planted core.fsmonitor never runs, and the answer still comes back"
  else
    fail "gitignored: a planted core.fsmonitor ran, or the ignored file read as not ignored"
  fi
  git -C "$FSM" check-ignore -q -- .work/x.sh >/dev/null 2>&1
  if [[ -e "$GI_ROOT/fsm-ran" ]]; then
    ok "gitignored fixture: plain git check-ignore runs the planted fsmonitor"
  else
    fail "gitignored fixture: the planted fsmonitor never fires, so the check above proves nothing"
  fi

  if hook::gitignored_out_of_scope "false" "$GREPO/.work/scratch.sh"; then
    ok "out_of_scope: ignored file with the opt-in off is out of scope"
  else
    fail "out_of_scope: ignored file with the opt-in off stayed in scope"
  fi
  if ! hook::gitignored_out_of_scope "true" "$GREPO/.work/scratch.sh"; then
    ok "out_of_scope: the opt-in 'true' keeps an ignored file in scope"
  else
    fail "out_of_scope: the opt-in 'true' did not keep the file in scope"
  fi
  if hook::gitignored_out_of_scope "yes; rm -rf /" "$GREPO/.work/scratch.sh"; then
    ok "out_of_scope: a garbage opt-in value reads as the default (off)"
  else
    fail "out_of_scope: a garbage opt-in value opened the gate"
  fi
  if ! hook::gitignored_out_of_scope "false" "$GREPO/src/plain.sh"; then
    ok "out_of_scope: an ordinary file stays in scope with the opt-in off"
  else
    fail "out_of_scope: an ordinary file was put out of scope"
  fi
  rm -rf "$GI_ROOT"
  unset GI_ROOT GREPO NOREPO OTHER
else
  ok "gitignore scope checks skipped (git absent)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
