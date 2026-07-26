#!/usr/bin/env bash
# Unit tests for the shared hook utility library. Tests source the canonical
# lib/hook-utils.sh directly and drive its functions in isolation; each
# plugin's own <plugin>.test.sh keeps the black-box hook contract tests.
# Because CI enforces that every plugin copy is byte-identical to the source,
# passing here covers the copies too.

set -uo pipefail

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

# make_sink <outfile> → prints the path to a single-executable stub sink that
# copies its stdin to <outfile>. The contract requires HOOK_TELEMETRY_SINK to be
# a single executable path (not a command-with-args), so tests point it at a
# stub script rather than `tee FILE`.
make_sink() {
  local s
  s="$(mktemp)"
  cat >"$s" <<EOF
#!/usr/bin/env bash
cat >"$1"
EOF
  chmod +x "$s"
  printf '%s' "$s"
}

# wait_for_sink <file> [max_polls] → block until <file> is non-empty (the
# fire-and-forget sink has flushed) or the bound elapses. Polls in 20ms steps so
# the assertion fires as soon as the write lands instead of racing a fixed sleep
# (sink dispatch is a freshly-spawned process; spawn latency varies, especially
# on Windows Git Bash). Returns non-zero on timeout so negative cases can assert.
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

# --- Test 1: HOOK_TELEMETRY_SINK unset → returns 0, no output ----------------
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

# --- Test 2: jq absent → fail-open (returns 0, no output) -------------------
# Make `command -v jq` genuinely fail by running with a PATH that contains no
# jq. A shell-function shadow does NOT exercise the guard: `command -v jq`
# reports a defined function as present, so the absence branch is never taken.
# emit_telemetry uses only shell builtins until its jq calls, so an empty PATH
# is sufficient. Scoped to the command so PATH/sink never leak into the suite.
EMPTY_BIN="$(mktemp -d)"
# shellcheck disable=SC2030,SC2031
out_nojq=$(
  export HOOK_TELEMETRY_SINK="cat"
  PATH="$EMPTY_BIN" hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"foo.py","findings":[]}' 2>/dev/null
)
rc_nojq=$?
rmdir "$EMPTY_BIN" 2>/dev/null || true
if [[ $rc_nojq -eq 0 ]]; then
  ok "jq absent: returns 0"
else
  fail "jq absent: expected 0, got $rc_nojq"
fi
if [[ -z "$out_nojq" ]]; then
  ok "jq absent: no output"
else
  fail "jq absent: unexpected output: $out_nojq"
fi

# --- Test 3: envelope shape matches schema (7 required common fields + data) --
SINK_FILE="$(mktemp)"
cleanup_t3() { rm -f "$SINK_FILE"; }
trap cleanup_t3 EXIT

# Use a file-writing sink to capture the envelope.
# shellcheck disable=SC2031  # prior subshell export is intentionally scoped there
HOOK_TELEMETRY_SINK="$(make_sink "$SINK_FILE")"
export HOOK_TELEMETRY_SINK
data_json='{"tool":"Write","file":"src/foo.py","findings":["src/foo.py:1:8: F401 os imported but unused"]}'
start=$EPOCHREALTIME
hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$start" "$data_json" 2>/dev/null
wait_for_sink "$SINK_FILE"
unset HOOK_TELEMETRY_SINK

if [[ -s "$SINK_FILE" ]]; then
  ok "envelope shape: sink received data"
  # Validate all 7 required common fields
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$SINK_FILE" >/dev/null 2>&1; then
      ok "envelope shape: field '$field' present"
    else
      fail "envelope shape: field '$field' missing. envelope=$(cat "$SINK_FILE")"
    fi
  done
  # Validate data sub-fields
  for subfield in tool file findings; do
    if jq -e ".data | has(\"$subfield\")" "$SINK_FILE" >/dev/null 2>&1; then
      ok "envelope shape: data.$subfield present"
    else
      fail "envelope shape: data.$subfield missing. data=$(jq .data "$SINK_FILE")"
    fi
  done
  # Validate schema_version
  sv=$(jq -r '.schema_version' "$SINK_FILE")
  if [[ "$sv" == "1.0" ]]; then
    ok "envelope: schema_version is 1.0"
  else
    fail "envelope: schema_version expected 1.0, got $sv"
  fi
  # Validate hook id
  hook_val=$(jq -r '.hook' "$SINK_FILE")
  if [[ "$hook_val" == "sample-hook" ]]; then
    ok "envelope: hook is sample-hook"
  else
    fail "envelope: hook expected sample-hook, got $hook_val"
  fi
  # Validate hook_event
  he=$(jq -r '.hook_event' "$SINK_FILE")
  if [[ "$he" == "PostToolUse" ]]; then
    ok "envelope: hook_event is PostToolUse"
  else
    fail "envelope: hook_event expected PostToolUse, got $he"
  fi
  # Validate status
  st=$(jq -r '.status' "$SINK_FILE")
  if [[ "$st" == "ok" ]]; then
    ok "envelope: status is ok"
  else
    fail "envelope: status expected ok, got $st"
  fi
else
  fail "envelope shape: sink file empty — emit did not fire or sink did not write"
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    fail "envelope shape: field '$field' not verifiable (no envelope)"
  done
  for subfield in tool file findings; do
    fail "envelope shape: data.$subfield not verifiable (no envelope)"
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
  # Verify it is genuinely UTC: timestamp hour must align with UTC hour (±1 for boundary)
  # We verify by checking the TZ=UTC prefix actually produces UTC
  utc_h=$(TZ=UTC date +%H)
  ts_h="${ts:11:2}"
  # Circular ±1h tolerance to absorb an hour-boundary straddle between the emit
  # and this check — including the 23→00 midnight wrap, where a linear distance
  # would read 23 and false-fail once per day. (#0 strips the leading zero so
  # 00–09 are not misread as octal inside (( )).)
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

# --- Test 5: duration_ms is a non-negative integer ---------------------------
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
trap - EXIT

# --- Test 6: status "skipped" passes through ---------------------------------
SINK_FILE2="$(mktemp)"
HOOK_TELEMETRY_SINK="$(make_sink "$SINK_FILE2")"
export HOOK_TELEMETRY_SINK
hook::emit_telemetry "sample-hook" "PostToolUse" "skipped" "$EPOCHREALTIME" '{"tool":"","file":"","findings":[]}' 2>/dev/null
wait_for_sink "$SINK_FILE2"
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

# --- Test 7: RELATIVE sink resolves against the passed repo_root (6th arg) ----
# This is the portable/tracked-wiring path: a relative HOOK_TELEMETRY_SINK joined
# onto the consuming repo root the caller passes.
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
wait_for_sink "$OUT7"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT7" ]] && [[ "$(jq -r '.hook' "$OUT7")" == "sample-hook" ]]; then
  ok "relative sink: resolved against repo_root arg, envelope delivered"
else
  fail "relative sink: not resolved against repo_root arg (out empty or wrong)"
fi
rm -rf "$ROOT7" "$OUT7"

# --- Test 8: RELATIVE sink resolves against CLAUDE_PROJECT_DIR when no root arg --
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
wait_for_sink "$OUT8"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT8" ]]; then
  ok "relative sink: resolved against CLAUDE_PROJECT_DIR fallback"
else
  fail "relative sink: CLAUDE_PROJECT_DIR fallback did not resolve"
fi
rm -rf "$ROOT8" "$OUT8"

# --- Test 9: RELATIVE sink with NO anchor → fail-open skip (return 0, no write) --
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

# --- Test 10: ABSOLUTE sink passes through unchanged --------------------------
OUT10="$(mktemp)"
ABS10="$(make_sink "$OUT10")" # mktemp path is absolute
export HOOK_TELEMETRY_SINK="$ABS10"
hook::emit_telemetry "sample-hook" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.py","findings":[]}' "/some/ignored/root" 2>/dev/null
wait_for_sink "$OUT10"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT10" ]] && [[ "$(jq -r '.hook' "$OUT10")" == "sample-hook" ]]; then
  ok "absolute sink: passes through unchanged (repo_root ignored)"
else
  fail "absolute sink: did not pass through"
fi
rm -f "$ABS10" "$OUT10"

# --- Test 11: hook::normalize_path is host-gated on OSTYPE --------------------
# The drive-letter fold is for Windows/MSYS only (case-insensitive FS). On a
# case-sensitive POSIX host a real single-letter top dir like /c/Repo must pass
# through unchanged, or the membership guard collapses it with /c/repo and
# admits a sibling outside CLAUDE_PROJECT_DIR. normalize_path reads the shell's
# OSTYPE, so override it in a subshell per case (the global stays intact).
norm_as() { (
  OSTYPE="$1"
  hook::normalize_path "$2"
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

# Windows/MSYS: fold both the POSIX /c/ and colon c:/ drive forms.
assert_norm msys "/c/Repo" "C:/repo" "msys folds /c/Repo → C:/repo"
assert_norm msys "C:/Repo" "C:/repo" "msys folds C:/Repo → C:/repo"
assert_norm msys "/c/Repo/Sub" "C:/repo/sub" "msys folds nested path"
assert_norm msys 'C:\Repo\x' "C:/repo/x" "msys: backslashes → slashes then fold"
assert_norm cygwin "/c/Repo" "C:/repo" "cygwin folds like msys"

# POSIX: NO fold — single-letter top dirs stay distinct (the regression guard).
assert_norm linux-gnu "/c/Repo" "/c/Repo" "linux leaves /c/Repo unchanged"
assert_norm linux-gnu "/c/repo" "/c/repo" "linux leaves /c/repo unchanged"
assert_norm linux-gnu "/opt/App/Sub" "/opt/App/Sub" "linux leaves normal path unchanged"
assert_norm linux-gnu 'a\b' "a/b" "linux still converts backslashes"

# Explicit guard: on POSIX the two casings must NOT collapse to one value.
if [[ "$(norm_as linux-gnu /c/Repo)" != "$(norm_as linux-gnu /c/repo)" ]]; then
  ok "normalize_path[linux-gnu]: /c/Repo and /c/repo stay distinct"
else
  fail "normalize_path[linux-gnu]: /c/Repo and /c/repo collapsed (membership-guard regression)"
fi

# --- Test 12: read_file_path membership guard — lexical and symlink cases ----
# Drives hook::read_file_path directly. Each case runs in a subshell so
# CLAUDE_PROJECT_DIR never leaks into the suite; JSON is built with jq so
# arbitrary mktemp paths are safely quoted. Symlink cases are attempted with
# MSYS=winsymlinks:nativestrict (real symlinks on Windows when Developer Mode
# allows; a no-op elsewhere) and SKIP-pass when the host cannot create one —
# MSYS ln -s otherwise silently copies, which would test nothing.
# MSYS_NO_PATHCONV / MSYS2_ARG_CONV_EXCL: Git Bash rewrites POSIX-looking
# arguments to Windows form when invoking a native exe like jq, which would
# feed the guard a converted file_path against an unconverted
# CLAUDE_PROJECT_DIR — a mixed-form pair production never produces (file_path
# arrives via stdin JSON and the project dir via env, neither is converted).
rfp() { # <project_dir> <file_path> → stdout: emitted path; rc: guard verdict
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -n --arg fp "$2" '{tool_input: {file_path: $fp}}' |
    (
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

# In-project file → accepted, caller's original path emitted.
if got=$(rfp "$PROJ12" "$PROJ12/inside.py") && [[ "$got" == "$PROJ12/inside.py" ]]; then
  ok "read_file_path: in-project file accepted, original path emitted"
else
  fail "read_file_path: in-project file rejected or path mangled (got '$got')"
fi

# Sibling directory sharing the root's name as a prefix → rejected.
if got=$(rfp "$PROJ12" "$SIB12/near.py"); then
  fail "read_file_path: prefix-sibling admitted (got '$got')"
else
  ok "read_file_path: prefix-sibling rejected"
fi

# Symlink inside the project pointing OUTSIDE it → rejected (the escape case).
if try_symlink "$OUTSIDE12/outside.py" "$PROJ12/escape.py"; then
  if got=$(rfp "$PROJ12" "$PROJ12/escape.py"); then
    fail "read_file_path: escaping symlink admitted (got '$got')"
  else
    ok "read_file_path: escaping symlink rejected"
  fi
else
  ok "read_file_path: escaping symlink SKIPPED (host cannot create symlinks)"
fi

# Symlink inside the project pointing INSIDE it → accepted (no over-reject).
if try_symlink "$PROJ12/inside.py" "$PROJ12/alias.py"; then
  if got=$(rfp "$PROJ12" "$PROJ12/alias.py") && [[ "$got" == "$PROJ12/alias.py" ]]; then
    ok "read_file_path: in-project symlink accepted, original path emitted"
  else
    fail "read_file_path: in-project symlink rejected or path mangled (got '$got')"
  fi
else
  ok "read_file_path: in-project symlink SKIPPED (host cannot create symlinks)"
fi

# Escape via a symlinked DIRECTORY inside the project → rejected.
if try_symlink "$OUTSIDE12" "$PROJ12/subdir"; then
  if got=$(rfp "$PROJ12" "$PROJ12/subdir/outside.py"); then
    fail "read_file_path: symlinked-directory escape admitted (got '$got')"
  else
    ok "read_file_path: symlinked-directory escape rejected"
  fi
else
  ok "read_file_path: symlinked-directory escape SKIPPED (host cannot create symlinks)"
fi

# Project root itself reached via a symlink (e.g. macOS /tmp) → file under the
# real root is still recognized as in-project (both sides canonicalized).
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

# --- Test 13: hook::telemetry_enabled — cheap sink-presence probe -------------
# Producers gate telemetry-payload construction on this, so its verdict must
# track HOOK_TELEMETRY_SINK exactly: unset and empty are disabled, any
# non-empty value is enabled.
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

# --- Test 14: hook::json_escape ----------------------------------------------
# Input via a variable: on Cygwin/MSYS bash a $'...' literal containing \r
# passed as a direct argument inside $(...) loses the CR at parse time.
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

# --- Test 15: hook::emit_skip_notice — valid JSON, both channels, jq-free -----
notice=$(hook::emit_skip_notice PostToolUse 'my-plugin: tool "x" missing — skipped')
if jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"
  and (.hookSpecificOutput.additionalContext | contains("missing"))
  and (.systemMessage | contains("missing"))' <<<"$notice" >/dev/null 2>&1; then
  ok "emit_skip_notice: valid JSON with both channels"
else
  fail "emit_skip_notice: bad JSON or missing fields: $notice"
fi
# jq-free path: PATH stripped of everything (tr fallback keeps the message).
EMPTY15="$(mktemp -d)"
notice_nojq=$(PATH="$EMPTY15" hook::emit_skip_notice PostToolUse "p: jq missing")
rmdir "$EMPTY15" 2>/dev/null || true
if [[ "$notice_nojq" == *'"systemMessage":"p: jq missing"'* ]]; then
  ok "emit_skip_notice: emits without any external binaries"
else
  fail "emit_skip_notice: empty-PATH emission broken: $notice_nojq"
fi
# Combined: distinct agent context + user message in ONE document.
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

# --- Test 16: hook::notice_once — per-session dedup via CLAUDE_PLUGIN_DATA ----
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
# No CLAUDE_PLUGIN_DATA → fail open toward visibility (emit every time).
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

# --- Test 16b: hook::raw_file_path — jq-free extraction -----------------------
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

# --- Test 17: hook::require_jq — gate behavior --------------------------------
# jq present → returns 0, no output, no exit.
out17=$( (
  hook::require_jq PostToolUse tp '{"session_id":"s"}'
  echo "alive"
) 2>/dev/null)
if [[ "$out17" == "alive" ]]; then
  ok "require_jq: jq present → pass-through"
else
  fail "require_jq: jq present misbehaved: $out17"
fi
# jq absent → notice on first run, exit 0; suppressed on second. Simulate the
# REAL missing-jq shape (Git Bash without jq): a stub PATH that still carries
# the coreutils notice_once needs (mkdir/find/tr) but no jq — an empty PATH
# would also hide mkdir, making the dedup marker untrackable and the notice
# fail-open on every run. bash is resolved via $BASH since the stub PATH has none.
DATA17="$(mktemp -d)"
FAKEBIN17="$(mktemp -d)"
for t in mkdir find tr; do
  real_t=$(command -v "$t")
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN17/$t"
  chmod +x "$FAKEBIN17/$t"
done
run17() {
  CLAUDE_PLUGIN_DATA="$DATA17" "$BASH" -c '
    PATH="'"$FAKEBIN17"'"
    source "'"$HOOK_DIR"'/hook-utils.sh"
    hook::require_jq PostToolUse tp "{\"session_id\":\"cccc-3333\"}"
    echo "unreachable"
  ' 2>/dev/null
}
first17=$(run17)
rc_first=$?
second17=$(run17)
rc_second=$?
if [[ $rc_first -eq 0 && "$first17" == *'"systemMessage"'* && "$first17" != *unreachable* ]]; then
  ok "require_jq: jq absent → visible notice + exit 0"
else
  fail "require_jq: first run rc=$rc_first out=$first17"
fi
if [[ $rc_second -eq 0 && "$second17" != *'"systemMessage"'* && "$second17" != *unreachable* ]]; then
  ok "require_jq: second run same session → silent exit 0"
else
  fail "require_jq: second run rc=$rc_second out=$second17"
fi
rm -rf "$DATA17" "$FAKEBIN17"

# --- git config value kinds + effective resolution ---------------------------
# The option walk must tag each collected -c/--config/--config-env value with its
# origin, and the effective-value projection must resolve a --config-env entry
# (an env-var NAME) to the variable's value the way git does at runtime.
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

# --- git_alias_expansion: structural classification of the invoked alias -------
# The guard RESOLVES inline (-c/--config) aliases but REFUSES an env (--config-env) alias
# for the invoked subcommand by shape — its expansion is an env var never read. git reads
# two spellings as the alias (`alias.<sub>` and `alias.<sub>.command`); the classifier
# keeps the LAST value WITHIN each spelling and fails closed on their union — env in
# either -> rc 2; else rc 0 exposing every present spelling's expansion in
# HOOK_GIT_ALIAS_EXPS (joined with '|' below, in plain-then-command order).

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

# A --config-env that sets a NON-alias key never triggers refusal (the legitimate use).
hook::git_resolve_subcommand 0 git --config-env=core.pager=PAGERVAR status
hook::git_alias_expansion status
rc=$?
if ((rc == 1)); then
  ok "git alias: --config-env non-alias key is not refused (resolvable/allowed)"
else
  fail "git alias (non-alias key): rc=$rc"
fi

# A --config-env alias for a subcommand OTHER than the invoked one is not refused.
hook::git_resolve_subcommand 0 git --config-env=alias.foo=AVAR status
hook::git_alias_expansion status
rc=$?
if ((rc == 1)); then
  ok "git alias: --config-env alias for an uninvoked subcommand is not refused"
else
  fail "git alias (uninvoked alias): rc=$rc"
fi

# LAST value WITHIN a spelling wins: env after inline for the same key -> refuse.
hook::git_resolve_subcommand 0 git -c alias.rh=status --config-env=alias.rh=AVAR rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 2)); then
  ok "git alias: env value last-wins over an inline decoy -> refuse"
else
  fail "git alias (env last): rc=$rc"
fi

# LAST value WITHIN a spelling wins: inline after env for the same key -> resolve inline.
hook::git_resolve_subcommand 0 git --config-env=alias.rh=AVAR -c alias.rh=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 0)) && [[ "$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")" == "status" ]]; then
  ok "git alias: inline value last-wins over an earlier env -> resolve (allowed)"
else
  fail "git alias (inline last): rc=$rc exps=[$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")]"
fi

# git config names are case-insensitive: the key match folds case.
hook::git_resolve_subcommand 0 git --config-env=alias.RH=AVAR rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 2)); then
  ok "git alias: --config-env key match folds case"
else
  fail "git alias (case fold): rc=$rc"
fi

# The `alias.<sub>.command` subkey is an alias definition too (git reads it), classified
# like the plain form: inline resolves, --config-env shape refuses.
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

# A non-`command` alias subkey is NOT an alias definition to git — must not be classified.
hook::git_resolve_subcommand 0 git -c alias.rh.nope=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 1)); then
  ok "git alias: a non-command alias subkey is not treated as an alias (rc 1)"
else
  fail "git alias (.nope control): rc=$rc"
fi

# LAST value WITHIN the .command spelling wins (independently of the plain spelling).
hook::git_resolve_subcommand 0 git -c alias.rh.command='reset --hard' -c alias.rh.command=status rh
hook::git_alias_expansion rh
rc=$?
if ((rc == 0)) && [[ "$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")" == "status" ]]; then
  ok "git alias: last value within the .command spelling wins"
else
  fail "git alias (.command within last): rc=$rc exps=[$(join_a "${HOOK_GIT_ALIAS_EXPS[@]}")]"
fi

# MAX-DANGER UNION: which spelling git runs when both are set is version-dependent, so the
# classifier exposes BOTH expansions and never lets one spelling mask the other. A benign
# value in either spelling must NOT collapse the sibling's expansion out of the result.
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

# Union on the ENV dimension: an env spelling refuses even when the sibling inline spelling
# is benign — the benign inline must not mask the unreadable env sibling.
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

# --- Test 18: hook::buffer_stdin — timeout path (return 2 / BLOCKED) ----------
# Incomplete JSON on a pipe that stays open past the read timeout must trip the
# bounded-read timeout branch: return 2 and a `BLOCKED:` diagnostic on stderr
# (the Win32-pipe late-EOF stall the bounded read exists to survive). Drives the
# real function: a producer emits a partial payload then sleeps to hold the pipe
# open, and STDIN_READ_TIMEOUT is shortened so the case is fast. jq present (this
# host) is what lets the function distinguish a truncated read from a small-but-
# complete one; without it the branch fails open to return 1, so this asserts the
# jq-present timeout shape specifically.
bs_rc_file="$(mktemp)"
bs_err_file="$(mktemp)"
{ printf '{"incomplete":'; sleep 1; } | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.4 hook::buffer_stdin >/dev/null 2>"$bs_err_file"
  echo "$?" >"$bs_rc_file"
}
bs_rc=$(cat "$bs_rc_file")
if [[ "$bs_rc" == "2" ]] && grep -q 'BLOCKED:' "$bs_err_file"; then
  ok "buffer_stdin: incomplete JSON past timeout → return 2 + BLOCKED on stderr"
else
  fail "buffer_stdin timeout: rc=$bs_rc err=$(cat "$bs_err_file")"
fi
rm -f "$bs_rc_file" "$bs_err_file"

# --- Test 19: hook::emit_telemetry — EPOCHREALTIME-absent (Bash < 5.0) skip ---
# On Bash < 5.0 EPOCHREALTIME is unset, so the caller's `start=${EPOCHREALTIME:-}`
# snapshot is empty. emit_telemetry must then skip fail-open (return 0, emit no
# envelope) rather than abort under `set -u` — the same silent-skip the caller's
# guard intends. Simulated by unsetting EPOCHREALTIME in the command-substitution
# subshell (its special attribute drops, so references yield empty), which does
# not leak into the rest of the suite. A wired sink proves nothing is dispatched.
tel19="$(mktemp)"
: >"$tel19"
sink19="$(make_sink "$tel19")"
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

# --- hook::extract_bash_subject: privacy-safe subject reduction --------------
# The subject is emitted verbatim into hook-events.jsonl and any wired
# HOOK_TELEMETRY_SINK, so it must never carry an assignment VALUE (a credential).
subject_is() {
  local desc="$1" tool="$2" cmd="$3" want="$4" got
  got=$(hook::extract_bash_subject "$tool" "$cmd")
  if [[ "$got" == "$want" ]]; then
    ok "extract_bash_subject: $desc"
  else
    fail "extract_bash_subject ($desc): want [$want] got [$got]"
  fi
}

# Leak case (the fix): a command whose LAST token is an unquoted assignment must
# NOT emit the value — it bails to the bare "Bash" subject.
subject_is "bare trailing assignment bails to Bash" \
  "Bash" "TOKEN=ghp_realtokenvalue" "Bash"
# A path-valued trailing assignment must bail BEFORE the basename strip, or the
# value's basename would leak (TOKEN=/a/b/secret -> "secret").
subject_is "path-valued trailing assignment bails (no basename leak)" \
  "Bash" "TOKEN=/a/b/secret" "Bash"
# Multiple assignments with no following command are all value — bail.
subject_is "trailing multi-assignment bails to Bash" \
  "Bash" "VAR=x TOKEN=secret" "Bash"
# Every valid Bash assignment form counts: append and subscripted assignments
# carry the value just the same.
subject_is "trailing append assignment bails to Bash" \
  "Bash" "TOKEN+=ghp_secret" "Bash"
subject_is "trailing subscripted assignment bails to Bash" \
  "Bash" "TOKEN[0]=ghp_secret" "Bash"
subject_is "trailing subscripted append assignment bails to Bash" \
  "Bash" "TOKEN[0]+=ghp_secret" "Bash"
subject_is "trailing nested-subscript assignment bails to Bash" \
  "Bash" "TOKEN[1+INDEX[0]]=ghp_secret" "Bash"

# Preserved: a following real command wins the token, so the assignment prefix is
# stripped and the command name is the subject.
subject_is "leading assignment prefix then a command yields the command" \
  "Bash" "VAR=x realcmd --flag arg" "Bash:realcmd"
# Preserved: a quoted assignment value still hits the quote-bail.
subject_is "quoted assignment value bails to Bash" \
  "Bash" 'TOKEN="a b" curl https://x' "Bash"
# Preserved: an ordinary command yields its basename subject, no tail.
subject_is "ordinary command yields basename subject" \
  "Bash" "/usr/bin/git status --short" "Bash:git"
# Preserved: a non-Bash tool returns its name unchanged.
subject_is "non-Bash tool returns the tool name" \
  "Write" "irrelevant" "Write"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
