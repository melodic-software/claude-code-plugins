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
# shellcheck disable=SC2030 # the subshell-local override is the point; Test 12b's later read of the host's real OSTYPE is what pairs this with SC2031
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
assert_norm linux-gnu 'a\b' "a/b" "linux still converts backslashes" # portability-ok: literal backslash in a path fixture, not a GNU grep \b word boundary

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

# --- Test 12b: read_file_path membership guard — Windows 8.3 short names ------
# GNU realpath under Git Bash does not expand 8.3 short names, so before
# hook::expand_8dot3 a short-form spelling of an IN-project file (the shape
# Claude Code's own scratchpad paths take) failed the prefix comparison and was
# silently skipped. Both sides are passed in Windows mixed form (C:/...), the
# form production hooks receive — a POSIX/mixed cross-form pair is a case
# production never produces (see Test 12's rfp note). 8.3 generation is a
# PER-VOLUME property: on a volume that does not generate short names the
# short-form fixture cannot be constructed, so these cases SKIP with a visible
# reason — read that skip as ABSENCE of coverage on this volume, never as the
# guard passing; only a generating volume exercises the defect.
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

  # A legitimate long name containing '~' must pass through untouched — the
  # expansion must never mistake it for a short name. Independent of whether
  # this volume generates short names ('note~s.py' fits 8.3, so none exists).
  if got=$(rfp "$PROJ12B_M" "$PROJ12B_M/note~s.py") && [[ "$got" == "$PROJ12B_M/note~s.py" ]]; then
    ok "read_file_path: literal-tilde long name accepted, original path emitted"
  else
    fail "read_file_path: literal-tilde long name rejected or mangled (got '$got')"
  fi

  if [[ -n "$short_in" && "$short_in" != "$plain_in" ]]; then
    # The regression: an in-project file spelled in short form is linted, not
    # silently skipped, and the caller's original (short) spelling is emitted.
    if got=$(rfp "$PROJ12B_M" "$short_in") && [[ "$got" == "$short_in" ]]; then
      ok "read_file_path: short-form in-project file accepted"
    else
      fail "read_file_path: short-form in-project file rejected (got '$got') — 8.3-blind membership guard"
    fi
    # The project dir itself in short form still admits its own files.
    short_proj=$(cygpath -s -m -- "$PROJ12B" 2>/dev/null)
    if got=$(rfp "$short_proj" "$PROJ12B_M/shortname-target.py") && [[ "$got" == "$PROJ12B_M/shortname-target.py" ]]; then
      ok "read_file_path: short-form project dir admits in-project file"
    else
      fail "read_file_path: short-form project dir rejected in-project file (got '$got')"
    fi
    # Short form must not defeat the deliberate out-of-project skip.
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

# --- Test 12c: read_file_path — the OS temp tree is not project content -------
# Prefix membership is not project membership. When CLAUDE_PROJECT_DIR is the
# user's home — the shape a session started outside any checkout takes — the
# harness's own per-session scratchpad under the OS temp root passes the prefix
# test, and every hook that scopes on this guard then lints, rewrites, or
# autocorrects a file that is not project content and has no project config to
# opt out with (#1769).
#
# The fixture mirrors that shape without depending on where this host puts its
# temp tree: an outer project root OUTSIDE any temp tree, with a stand-in temp
# root nested inside it that TMPDIR/TMP/TEMP point at for the duration of the
# case. $HOME is the one portable location guaranteed to sit outside the temp
# tree on both hosts; when it does not (an exotic CI whose HOME is itself under
# temp), the shape cannot be built and the cases SKIP with a visible reason —
# absence of coverage, never a pass.
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
if [[ -n "$PROJ12C" ]] && ! hook::under_temp_root "$(hook::normalize_path "$(hook::physical_path "$PROJ12C")")"; then
  mkdir -p "$PROJ12C/scratchpad"
  echo 'y = 2' >"$PROJ12C/scratchpad/inventory.py"
  echo 'x = 1' >"$PROJ12C/inside.py"

  # THE REGRESSION: a file in the temp tree, reached from a project root that is
  # not itself in the temp tree, is scratch — not project content.
  if got=$(rfp_tmp "$PROJ12C/scratchpad" "$PROJ12C" "$PROJ12C/scratchpad/inventory.py"); then
    fail "read_file_path: temp-tree file admitted under a non-temp project root (got '$got') — home-shaped project dir admits the harness scratchpad"
  else
    ok "read_file_path: temp-tree file rejected under a non-temp project root"
  fi

  # The exemption the fix must preserve: when the project root IS the temp root,
  # a file under it is the project (a `mktemp -d` fixture checkout — how this
  # repo's own hook suites run), so the branch must stay quiet.
  if got=$(rfp_tmp "$PROJ12C/scratchpad" "$PROJ12C/scratchpad" "$PROJ12C/scratchpad/inventory.py") &&
    [[ "$got" == "$PROJ12C/scratchpad/inventory.py" ]]; then
    ok "read_file_path: temp-rooted project still admits its own files"
  else
    fail "read_file_path: temp-rooted project rejected its own file (got '$got') — the mktemp-fixture exemption regressed"
  fi

  # Control: an in-project file outside the temp tree is unaffected.
  if got=$(rfp_tmp "$PROJ12C/scratchpad" "$PROJ12C" "$PROJ12C/inside.py") &&
    [[ "$got" == "$PROJ12C/inside.py" ]]; then
    ok "read_file_path: in-project file outside the temp tree still accepted"
  else
    fail "read_file_path: in-project file outside the temp tree rejected (got '$got')"
  fi

  # Windows spells its temp root with backslashes: TMP/TEMP arrive as a
  # drive-letter path with backslash separators, while TMPDIR carries the POSIX
  # form of a DIFFERENT spelling of the same directory. A candidate list that
  # only handles the POSIX form recognizes nothing on the host where this defect
  # was reported, so the backslash spelling is exercised on its own.
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

# --- Test 12d: under_temp_root — the filesystem root as a temp candidate ------
# A candidate of `/` contains every absolute path. Trimming its trailing slash
# empties the string, and an empty candidate is discarded — so `TMPDIR=/` used
# to recognize nothing at all instead of everything.
if (
  # shellcheck disable=SC2030,SC2031 # subshell-local by design: the overrides must not leak into the suite
  export TMPDIR=/ TMP=/ TEMP=/
  hook::under_temp_root "$HOME/anywhere/at-all.py"
); then
  ok "under_temp_root: root temp candidate contains every path"
else
  fail "under_temp_root: root temp candidate discarded — '/' trimmed to empty"
fi

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

# --- The release handshake, used by every held-open-pipe case below -----------
# A case that needs a stall declared BEFORE EOF is bounded by the producer's
# hold, not by the read timeout: reaching a stall costs the bound PLUS the two
# subshell forks buffer_stdin spends resolving its timeout and slice, PLUS a jq
# probe — and a fork on this platform has been measured between 93 ms and 3.2 s.
# Every fixed `sleep` hold in this file was therefore a constant guessed against
# an unbounded quantity, and each one was observed failing in turn: 1 s, then 5 s,
# then the timing helpers' 3 s and 4 s holds, all outrun by spawns, each showing
# up as rc 1 (EOF first, so no stall) or as a comparison measuring the hold
# instead of the behavior.
#
# The handshake removes the constant instead of retuning it. Opening a FIFO for
# READ blocks until a writer appears, so the producer stays alive — and its
# stdout stays open, so the consumer never sees EOF — until the consumer opens
# the same FIFO for write, which it does once it has its verdict. Both sides are
# builtins with redirects; a `cat` would put a spawn back on the very path this
# exists to keep spawns off. Measured: the pipeline ends at consumer completion
# (2271 ms for a 2000 ms consumer) where a fixed 8 s hold cost 8180 ms — so this
# is also what makes the repeated sampling further down affordable.
bs_release_fifo="$(mktemp -u)"
bs_mkfifo_err=$(mkfifo "$bs_release_fifo" 2>&1)
if [[ -z "$bs_mkfifo_err" ]] && [[ -p "$bs_release_fifo" ]]; then
  bs_hold_open() { read -r _ <"$bs_release_fifo"; }
  bs_release() { : >"$bs_release_fifo"; }
else
  # Say so, loudly. Dropping to the fallback costs minutes of extra wall time
  # across the cases below, and without this line the only symptom is a run that
  # is mysteriously slower — indistinguishable from the host being busy, which is
  # the exact confusion this whole file is about. The reason mkfifo refused is
  # part of the message because a container or network filesystem that rejects
  # FIFOs is the plausible way to get here, and that is worth knowing.
  printf 'WARNING: mkfifo unavailable (%s); buffer_stdin cases fall back to a fixed hold, which is slower and less precise.\n' \
    "${bs_mkfifo_err:-no FIFO created}" >&2
  # No FIFO on this host: fall back to a fixed hold, which is what this replaced.
  # It has to clear the WORST case any call site can reach, and the worst is the
  # stall comparison's unsliced arm. That arm pays TWO whole bounds, not one:
  # unsliced, the first 3.6 s read returns WITH the early bytes and only the
  # second empty one declares the stall (which is the overshoot the sliced form
  # exists to cap — see Test 18g). So 7.2 s of bounds plus three sequential
  # forks, which at the 3.2 s per-fork figure measured above is ~16.8 s; a
  # measured pass of that arm came in at 10593 ms on a box that was not at its
  # worst. This comment previously counted ONE bound and derived ~13.2 s, which
  # is under the real worst case; a 12 s constant would have been under it by
  # more, reintroducing exactly the truncation this replaced. 60 s is ~3.5x the
  # derived worst case, so it stays adequate on the corrected arithmetic. The
  # honest trade, since the comment here previously claimed there was none: a
  # too-short hold turns a should-pass into a false fail, and a long one costs
  # wall time on a host that reaches it.
  # This path is best-effort — Linux and MSYS both provide mkfifo, so it is not
  # expected to run — and it buys correctness with time rather than the reverse.
  bs_hold_open() { sleep 60; }
  bs_release() { :; }
fi

# --- Test 18: hook::buffer_stdin — timeout path (return 2 / BLOCKED) ----------
# Incomplete JSON on a pipe that stays open past the read timeout must trip the
# bounded-read timeout branch: return 2 and a `BLOCKED:` diagnostic on stderr
# (the Win32-pipe late-EOF stall the bounded read exists to survive). Drives the
# real function: a producer emits a partial payload then holds the pipe open, and
# STDIN_READ_TIMEOUT is shortened so the case is fast. jq present (this host) is
# what lets the function distinguish a truncated read from a small-but-complete
# one; without it the branch fails open to return 1, so this asserts the
# jq-present timeout shape specifically.
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
if [[ "$bs_rc" == "2" ]] && grep -q 'BLOCKED:' "$bs_err_file"; then
  ok "buffer_stdin: incomplete JSON past timeout → return 2 + BLOCKED on stderr"
else
  fail "buffer_stdin timeout: rc=$bs_rc err=$(cat "$bs_err_file")"
fi
rm -f "$bs_rc_file" "$bs_err_file"

# --- Test 18b: hook::buffer_stdin — stall AFTER a complete payload succeeds ---
# The Win32-pipe late-EOF case the bounded read exists for: the producer emits a
# COMPLETE JSON payload and then holds the pipe open past the read timeout. The
# read still stalls, but jq confirms the payload is whole, so the function must
# return it (rc 0) rather than block. This is the half of the contract that keeps
# the chunked read from turning every slow producer into a blocked tool call.
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

# ...and it must cost ONE window, not two. Re-arming on progress would otherwise
# spend a second full window waiting for an EOF this producer never sends,
# doubling the delay the bound is supposed to cap; the loop therefore stops as
# soon as the buffer already parses as whole JSON. One window is the floor —
# until a window expires, a held-open pipe is indistinguishable from a slow one.
#
# There is no non-clock proxy to convert this to: both the correct and the
# reading-on implementations return rc 0 and the identical payload, so latency is
# the only observable that tells them apart. Everything below is about making a
# latency comparison that a loaded host cannot SYSTEMATICALLY invert. Not one it
# cannot invert at all: item 3 below is the correction of exactly that claim, and
# single deltas of -631 ms and -1012 ms have been measured here. What the
# machinery buys is that inversions stay isolated samples the estimator discards,
# instead of a standing offset that survives into the verdict.
#
# TWO PROPERTIES DO THE WORK, and a third that was claimed here does not.
#
# 1. The slow arm must do strictly MORE work than the fast one in every
#    dimension. The override therefore performs the real completeness check and
#    only LIES about the verdict. An override that SKIPPED the work
#    (`json_complete() { return 1; }`, used here until 2026-08-09) made the slow
#    arm pay ZERO jq forks while the fast arm paid one, so on a host where a
#    spawn costs seconds the "slow" arm won: 4855 ms fast vs 4330 ms slow, an
#    inverted result. The ledger is now fast = 1 read + 1 fork against slow =
#    5 reads + 3 forks (two json_complete probes plus the `validated=0` probe at
#    hook-utils.sh:586, which only the slow arm reaches).
#
# 2. The producer must hold its stdout open until the CONSUMER is done. A fixed
#    `sleep` cannot do that: reaching the slow arm's verdict costs the bound plus
#    buffer_stdin's startup spawns, and when those spawns outran the hold, EOF cut
#    the slow arm short and the comparison measured the hold instead of the
#    behavior (the same run: slow arm 4330 ms against a 3 s hold). bs_hold_open
#    replaces the sleep with a handshake, so the hold is exactly as long as the
#    consumer needs and no constant has to be guessed.
#
# 3. NOT TRUE, and was asserted here: that more work on the slow side means "no
#    amount of load can invert" the result. The two arms are separate processes
#    run SEQUENTIALLY, so they never share a load sample — dominance holds in
#    expectation, not per sample. Instrumenting buffer_stdin's two startup forks
#    across four back-to-back runs on an idle box gave 93/92, 762/1277,
#    1755/3234, 107/100 ms: a 35x swing on ONE fork, up to 3.2 s. The structural
#    gaps it has to be read against are 1.2 s for this case (one slice against a
#    whole bound plus a slice) and 2.7 s for the stall case below, so a single
#    bad fork exceeds one of them outright and eats most of the other. Since each
#    arm pays several forks, single-sample comparison is not measurable here at
#    all — which is why these cases take N interleaved samples per arm and
#    compare an ORDER-BALANCED median of the paired deltas: a median inside each
#    order group, averaged across the two groups (bs_paired_estimate). The median
#    is robust to the occasional multi-second fork, which one sample is not, and
#    the grouping is what keeps a systematic order bias from riding through it.
#
# Timing is taken INSIDE the consumer: bracketing the pipeline would fold the
# producer and the handshake into the measurement.

# bs_median <n> ... — the middle value. Used instead of a mean because the noise
# is a heavy tail (one 3.2 s fork in four samples), which a mean would swallow.
# At an even count this returns the LOWER middle rather than averaging the two;
# every caller here passes an odd-sized group, and where it does not the choice
# is conservative rather than pass-favoring.
bs_median() { printf '%s\n' "$@" | sort -n | awk '{v[NR] = $0} END {print v[int((NR + 1) / 2)]}'; }

# bs_paired_estimate <a-first deltas...> -- <b-first deltas...> — prints
# "<estimate> <a-first median> <b-first median>", the order-balanced estimate of
# B-minus-A in ms. Returns 1 (printing nothing) if the separator is missing or
# the two groups are not the same size.
#
# Every delta inside ONE group carries the SAME order bias, because every pair in
# it ran in the same order: +δ where A ran first, since B then paid the
# second-position penalty, and -δ where B ran first. So a statistic taken
# symmetrically across the two groups cancels δ exactly, whatever δ is, while the
# same statistic POOLED over both groups does not — see bs_samples.
#
# The median WITHIN each group keeps the outlier rejection a pooled median had:
# a lone multi-second fork never moves its group's median. The mean ACROSS the
# two groups is what cancels the bias, and a mean is correct there precisely
# because its two inputs are equal-sized and oppositely biased. Equal size is the
# load-bearing precondition, so it is checked rather than assumed — an odd sample
# count would split 3/2 and cancel only part of the bias.
bs_paired_estimate() {
  local -a a_first=() b_first=()
  local seen_sep=0 arg m_a m_b
  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
      seen_sep=1
      continue
    fi
    if ((seen_sep)); then b_first+=("$arg"); else a_first+=("$arg"); fi
  done
  ((seen_sep == 1)) || return 1
  ((${#a_first[@]} > 0)) || return 1
  ((${#a_first[@]} == ${#b_first[@]})) || return 1
  m_a=$(bs_median "${a_first[@]}")
  m_b=$(bs_median "${b_first[@]}")
  printf '%s %s %s' "$(((m_a + m_b) / 2))" "$m_a" "$m_b"
}

# bs_paired_verdict <label> <slack-ms> <a-name> <b-name> — asserts that the
# order-balanced estimate of B-minus-A clears <slack-ms>, reading the two order
# groups bs_samples just filled. Prints BOTH group medians and every delta, so a
# marginal pass is visible in the log rather than hidden behind the summary — and
# so the size of the order bias, which is the gap between the two group medians,
# is on the record for every run rather than inferred.
bs_paired_verdict() {
  local label="$1" slack="$2" a="$3" b="$4" est m_a m_b out detail
  if ! out=$(bs_paired_estimate "${bs_deltas_a_first[@]}" -- "${bs_deltas_b_first[@]}"); then
    fail "$label: order groups are not balanced (${#bs_deltas_a_first[@]} vs ${#bs_deltas_b_first[@]}); the sample count must be even"
    return
  fi
  read -r est m_a m_b <<<"$out"
  detail="slack ${slack} ms; $a-first median ${m_a}, $b-first median ${m_b};"
  detail="$detail deltas ${bs_deltas_a_first[*]} | ${bs_deltas_b_first[*]}"
  if ((est >= slack)); then
    ok "$label: order-balanced $b-minus-$a is ${est} ms ($detail)"
  else
    fail "$label: order-balanced $b-minus-$a is only ${est} ms, under the ${slack} ms slack ($detail)"
  fi
}

# bs_samples <n> <fn> <arm-a-arg> <arm-b-arg> — runs <fn> alternately with each
# argument, INTERLEAVED, so the two arms sample the same load window rather than
# two different ones. Fills bs_deltas_a_first and bs_deltas_b_first with the
# per-pair B-minus-A delta, SPLIT BY THE ORDER THE PAIR RAN IN, or empties both
# if any sample came back untimed. <n> must be EVEN, so the two groups come out
# the same size and bs_paired_estimate can cancel the order bias with them.
#
# The ORDER within each pair alternates, A-then-B on even pairs and B-then-A on
# odd ones, while the subtraction stays B-minus-A throughout. Running A first
# every time would put any order-dependent cost — a host that launches later
# processes more slowly, or a monotonic warm-up or drift across the pair — into
# every delta with the same sign, and a MEDIAN removes isolated outliers but not
# a systematic bias. Left uncorrected on a slow-spawning host, that bias is
# indistinguishable from the behavior gap being measured, so a regression that
# made the arms equally fast could still clear the slack.
#
# ALTERNATION ALONE DOES NOT CANCEL IT. This claimed until 2026-08-09 that the
# second-position penalty lands on A for half the pairs and on B for the other
# half, "so it cancels in the median" — it does not, which is why the deltas are
# now kept in two groups and combined by bs_paired_estimate instead of pooled. A
# median pooled over both orders lands INSIDE whichever group is larger and keeps
# that group's bias in full: at the odd n=5 this used to take, the 3/2 split put
# the pooled median at g+δ, and the majority group was the PASS-favoring one.
# Driving the shipped helpers with a fully regressed mechanism (true gap zero) on
# a host with a ±500 ms order bias produced deltas of 500 -500 500 -500 500 and a
# pooled median of 500 ms — a PASS against the 400 ms slack for a mechanism that
# had stopped working entirely. The mean of those same five numbers is 100 ms.
# That reproduction is asserted directly against bs_paired_estimate below.
bs_deltas_a_first=()
bs_deltas_b_first=()
bs_samples() {
  local n="$1" fn="$2" arg_a="$3" arg_b="$4" i a b
  bs_deltas_a_first=()
  bs_deltas_b_first=()
  for ((i = 0; i < n; i++)); do
    if ((i % 2 == 0)); then
      a=$("$fn" "$arg_a")
      b=$("$fn" "$arg_b")
    else
      b=$("$fn" "$arg_b")
      a=$("$fn" "$arg_a")
    fi
    if [[ -z "$a" || -z "$b" ]]; then
      bs_deltas_a_first=()
      bs_deltas_b_first=()
      return 1
    fi
    # Which array a delta lands in IS its order group — recorded where the order
    # is decided, rather than re-derived later from a position in one flat list.
    if ((i % 2 == 0)); then
      bs_deltas_a_first+=("$((b - a))")
    else
      bs_deltas_b_first+=("$((b - a))")
    fi
  done
}

# --- Test 18b(i): the paired estimator cancels a systematic order bias --------
# The acceptance test for the correction above, and the one assertion in this
# neighborhood that needs no clock at all: feed the SHIPPED estimator synthetic
# deltas describing a fully regressed mechanism — true gap ZERO — measured on a
# host with a ±500 ms order bias. It must report ~0 and stay under the 400 ms
# slack the two timing cases use. The pooled median it replaced reported 500 ms
# for exactly these numbers, i.e. it passed a mechanism that had stopped working.
#
# The second vector is the other half of the property: the same ±500 ms bias laid
# over a REAL 1000 ms gap must still come back as 1000, so the fix cancels the
# bias rather than deflating the signal along with it. The third asserts the
# equal-size precondition is enforced, since partial cancellation would be a
# silent return to the defect.
bs_est_zero=$(bs_paired_estimate 500 500 500 -- -500 -500 -500)
bs_est_real=$(bs_paired_estimate 1500 1500 1500 -- 500 500 500)
bs_est_unbalanced_rc=0
bs_paired_estimate 500 500 -- -500 >/dev/null || bs_est_unbalanced_rc=$?
if [[ "${bs_est_zero%% *}" == "0" ]] && ((${bs_est_zero%% *} < 400)) &&
  [[ "${bs_est_real%% *}" == "1000" ]] && ((bs_est_unbalanced_rc == 1)); then
  ok "paired estimator: a ±500 ms order bias cancels (zero gap → ${bs_est_zero%% *} ms, under the 400 ms slack; 1000 ms gap → ${bs_est_real%% *} ms), and unequal groups are rejected"
else
  fail "paired estimator: zero-gap '$bs_est_zero' (want 0, under 400), real-gap '$bs_est_real' (want 1000), unequal-group rc=$bs_est_unbalanced_rc (want 1)"
fi

bs_time_late_eof() { # $1 = shell prelude; prints elapsed ms (empty if untimed)
  local t_file
  t_file="$(mktemp)"
  {
    printf '{"complete":true}'
    bs_hold_open
  } | {
    CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1.2 bash -c '
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
# Mirrors hook::json_complete's real `printf | jq -e .` body (never a here-string
# — see that function: a here-string at pipe capacity deadlocks the shell), then
# returns 1 regardless. Same spawn, opposite verdict.
# shellcheck disable=SC2016 # $1 is the overriding function's own positional, not this shell's
bs_reads_on='hook::json_complete() { printf "%s" "$1" | jq -e . >/dev/null 2>&1; return 1; }'
if bs_samples 6 bs_time_late_eof "" "$bs_reads_on"; then
  bs_paired_verdict "buffer_stdin: late-EOF stops at the payload, not the bound" \
    400 fast slow
elif [[ -n "${EPOCHREALTIME:-}" ]]; then
  # On a host that HAS EPOCHREALTIME an empty measurement means the harness
  # broke, which would silently turn this case into a vacuous pass.
  fail "late-EOF timing harness produced no measurement"
else
  ok "buffer_stdin: late-EOF window count not timed (EPOCHREALTIME absent, Bash < 5.0)"
fi
rm -f "$bs_rc_file" "$bs_out_file"

# --- Test 18c: hook::buffer_stdin — a large payload is neither blocked nor slow -
# Regression for the defect the chunked read fixes: `read -d ''` consumed a pipe
# byte-at-a-time, so the timeout was a throughput ceiling and a ~100 KB payload —
# an ordinary full-file Write of a long document — tripped the stall branch and
# every fail-closed caller blocked it. Drives a 256 KB payload (comfortably past
# the old ~64 KB ceiling and past the 64 KB chunk size, so the read loop iterates)
# through the real function on a real pipe, at the DEFAULT timeout: it must come
# back whole, with rc 0. Asserted on content, not on wall-clock, so a loaded CI
# runner cannot flake it — but if the byte-at-a-time read ever returns, this case
# fails outright rather than merely slowing down.
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

# --- Test 18d: hook::buffer_stdin — the bound is IDLE, not per-read total -----
# `read -t` is a deadline for the whole requested read, not an inactivity timer,
# so a producer that keeps delivering but slower than one chunk per window would
# trip it even though the pipe is never idle. buffer_stdin must keep a timed-out
# read's partial bytes and re-arm. Producer emits one character every 100 ms
# against a 1.2 s idle bound — far too slow to fill a 65536-byte chunk in any
# single window — then closes. Expect the whole payload back with rc 0.
#
# Two ratios keep this off the wall clock, and they pull in opposite directions:
#
#  * The producer must OUTLIVE a whole bound, or the read never has to re-arm and
#    the case is vacuous. 20 x `sleep 0.1` is 2.0 s of production against a 1.2 s
#    bound, and `sleep` never returns EARLY — so that ratio holds by construction
#    on any host, however loaded. Load only lengthens it.
#  * The per-byte gap must stay under the idle bound, or the guard declares a
#    stall that is not one. This is the load-sensitive direction, and the gap has
#    to be produced WITHOUT a process spawn to survive it — see bs_tick. At the
#    original 100 ms `sleep` gap against a 300 ms bound the margin was nominally
#    3x and this case FAILED on a loaded Windows box on 2026-08-09 (rc 2, empty
#    payload); widening the bound to 1.2 s did not fix it, because the gap was
#    never really 100 ms — it was 100 ms plus a spawn, and the spawn was the
#    larger and more variable term. With a spawn-free gap the 12x margin is real.
#
# bs_tick <seconds> — a delay that spawns NOTHING. A FIFO opened READ-WRITE never
# reaches EOF and never delivers a byte, so `read -t` against it is a pure
# builtin timer. Measured here: five 0.1 s ticks cost 546 ms this way against
# 1401 ms for five `sleep 0.1`, and the `sleep` figure is the one that balloons
# under load.
#
# FRACTIONAL `read -t` is the precondition, and it is not universal: Bash 3.2 —
# the macOS system shell these hooks document support for — rejects `0.1`
# outright, and a rejected read returns IMMEDIATELY. That failure is silent and
# far worse than the problem being fixed: with a zero-length tick the producer
# emits all 20 bytes at once, the read never has to re-arm, and the case passes
# while testing nothing. So the support is probed the way
# hook::resolve_read_slice probes it — a `read -t` against /dev/null, judged by
# whether it printed a usage error — before the FIFO is created at all, and the
# `sleep` spawn is the fallback for that host as well as for one where a FIFO
# cannot be made. Falling back is no worse than what this replaces. The tick is
# then asserted to actually DELAY, so neither branch can go vacuous unnoticed.
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
# Lower bound only, so load can never flake it: five 0.1 s ticks must cost at
# least 400 ms of the nominal 500 ms. A tick that silently does not delay — the
# Bash 3.2 hazard above, or a FIFO that turns out to deliver — lands near 0 ms
# and fails here rather than hollowing out the case below.
#
# One host is left unguarded and it is not reachable from here: Bash 4.x, which
# HAS fractional `read -t` (so the probe selects the FIFO) but lacks
# EPOCHREALTIME (so this takes the untimed branch and cannot check it). The tick
# is exercised for real there — it just is not measured. Timing it would need an
# external clock, i.e. the process spawn per sample that this whole mechanism
# exists to avoid, so the guard is left where the measurement is free.
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

# And the other side of the same contract: a trickle that then goes SILENT with
# an incomplete payload must still fail closed. Re-arming on progress must not
# become "never time out". The bound stays SHORT here on purpose: this case needs
# the stall declared before the producer stops holding, so load pushing the gaps
# out only makes it fire sooner. It has no flaky direction, which is why it keeps
# the 0.3 s bound the case above had to give up — but it does need the release
# handshake, not a fixed hold: a 5 s hold was still outrun by buffer_stdin's
# startup spawns and this failed with rc 1 (EOF first, so no stall).
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

# --- Test 18e: hook::buffer_stdin — the pre-4.1 (`read -d ''`) branch ---------
# `read -N` is Bash 4.1+; macOS ships 3.2 and these hooks document 3.2+ support,
# so the function falls back to the delimiter read below 4.1. CI and this host
# run a modern bash, and BASH_VERSINFO is readonly so it cannot be shadowed —
# hence the guard lives in its own predicate, which the child shell overrides to
# select the fallback path FOR REAL rather than simulating it. First assert the
# override actually flips the branch (otherwise these cases would be vacuous),
# then that the fallback buffers a whole large payload and still fails closed.
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
# Held by the handshake, not a constant: this variant adds a whole `bash -c` on
# top of buffer_stdin's own startup spawns, so it is the hardest one here to size
# a fixed hold for.
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

# --- Test 18f: hook::buffer_stdin — an unusable stdin_read_timeout ------------
# stdin_read_timeout is consumer-configurable and reaches `read -t` directly, so
# an unusable value is a silent DISABLE, not a tuning mistake: `read` rejects a
# bad spec with rc 1 (which the loop reads as EOF → empty payload → every caller
# skips) and prints a usage error on stderr on every hook invocation. `0` is
# worse — `read -t 0` returns success having consumed nothing, which spins the
# loop until the harness kills the hook. Both must degrade to the default and
# still deliver the payload. The `0` case doubles as the loop-termination test:
# before the guard it hung outright, so a regression here shows up as this suite
# never finishing.
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

# A VALID non-default value must still be honored — the guard must not collapse
# every setting to the default. 0.5 s against a producer that holds the pipe until
# the verdict is in, so the stall cannot lose a race with EOF.
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

# --- Test 18g: hook::buffer_stdin — a stall lands near ONE bound, not two -----
# `read -t` reports only that its window expired, never WHEN inside it the last
# byte arrived. Armed as a single window, a producer that emits bytes early and
# then goes quiet is not declared stalled until the SECOND window expires —
# almost twice the configured bound. Reading the bound in slices caps that
# overshoot at one slice. Asserted by comparison against a variant with the slice
# count forced to 1 (the unsliced behavior), sampled as INTERLEAVED PAIRS so the
# two arms see the same load window. Runner load does NOT cancel — that is what
# this said until 2026-08-09, and it was wrong twice over: the arms are separate
# sequential processes that never share a load sample, and the code has not been
# a single back-to-back pair since the sampling went in. Interleaving only keeps
# a load spike from landing systematically on one arm; the estimator is what
# discards it. The override is asserted to actually engage first — a silently
# ineffective override would make this a vacuous pass, which has already happened
# twice on this branch.
#
# There is no non-clock proxy: both variants end in the same rc 2 stall with the
# same empty payload, and only WHEN the stall is declared differs, which is the
# whole property under test. Three things had to change for the comparison to
# hold on a loaded host, and the 2026-08-09 runs show all three:
#
#  * The HOLD has to outlast the SLOW arm. The unsliced arm read 4293 ms against
#    a 4 s hold — EOF had cut it off, so the comparison was measuring the hold
#    rather than the overshoot. bs_hold_open now ends the hold when the consumer
#    says so, which removes the constant rather than retuning it.
#  * Unlike the late-EOF case, this one's arms are NOT symmetric in work: the
#    sliced arm does slice_count+1 reads where the unsliced does 2, and it is the
#    arm that has to finish FIRST. Every read costs a wakeup, so load taxes
#    precisely the arm that must win. Measured on Windows Git Bash at ~420 ms per
#    extra read, so the three extra reads eat ~1.26 s of whatever gap the bound
#    provides — and that tax is FIXED per read, it does not grow with the bound.
#    At a 2.4 s bound the gap is 1.8 s, leaving ~0.5 s of true signal against a
#    400 ms slack: measured, the median came in at 532 ms, a 1.33x margin that
#    would flake. The bound is therefore 3.6 s, where the gap is 2.7 s (0.9 s
#    slice + 3.6 s against two 3.6 s bounds) and the tax leaves ~1.4 s — 3.6x the
#    slack, and clear of the estimator's own sampling error at six pairs. Growing
#    the bound is the only lever that grows the signal, because the tax does not
#    scale with it and no tolerance can be set below it.
#  * ONE sample of each arm decides nothing. The startup-fork swing documented
#    above the late-EOF case (up to 3.2 s on a single fork) dwarfs even a 1.8 s
#    gap on a bad sample, so this takes 6 interleaved pairs and compares the
#    ORDER-BALANCED estimate. Every delta and both group medians are printed, so
#    a marginal pass — and the order bias itself — is visible per run.
bs_time_stall() { # $1 = shell prelude; prints elapsed ms (empty if untimed)
  local t_file
  t_file="$(mktemp)"
  # Bytes land immediately, then the pipe goes quiet past two whole bounds.
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
# The unsliced override must pay the same COMMAND SUBSTITUTION the real
# hook::resolve_read_slice pays at hook-utils.sh:491 to probe its slice value.
# `printf "%s 1" "$1"` alone — what this was until 2026-08-09 — forks zero times
# where the sliced arm forks once, and it is the arm that must come out SLOWER,
# so the missing fork shrinks the very gap this case measures. On a host where a
# fork has been measured at up to 3.2 s that is enough to invert the result: the
# run that exposed it had two of five paired deltas negative. Identical mistake
# to the json_complete override above, in a second place; the rule is that an
# override may lie about a VERDICT but must never skip the WORK.
# shellcheck disable=SC2016 # $1 is the overriding function's own positional, not this shell's
bs_unsliced='hook::resolve_read_slice() {
  local probe
  probe=$(read -r -t "$1" discard </dev/null 2>&1)
  printf "%s 1" "$1"
}'
bs_slices=$(bash -c 'source "$1"; hook::resolve_read_slice 3.6' _ "$HOOK_DIR/hook-utils.sh")
bs_slices_forced=$(bash -c 'source "$1"; '"$bs_unsliced"'; hook::resolve_read_slice 3.6' \
  _ "$HOOK_DIR/hook-utils.sh")
if [[ "$bs_slices" == "0.900 4" ]] && [[ "$bs_slices_forced" == "3.6 1" ]]; then
  ok "buffer_stdin: slice resolution splits the bound, and the unsliced override engages"
else
  fail "slice resolution: got '$bs_slices' / forced '$bs_slices_forced'; cases below are vacuous"
fi
# A late-EOF payload whose length lands exactly on a 65536-character read
# boundary completes on a read that returns rc 0, so it never reaches the
# with-bytes completeness check — only the empty-slice one catches it. Without
# that, this case waits out the whole bound instead of a slice.
#
# THE LATENCY HALF OF THIS CASE HAS BEEN REMOVED AS UNMEASURABLE. It compared the
# boundary payload against a deliberately non-boundary one of the same shape, and
# unlike the two comparisons above, its arms are structurally IDENTICAL — one
# slice and one jq probe each — so there is no work asymmetry for the tolerance
# to sit inside, and nothing but the regression separates them. The evidence,
# collected 2026-08-09 on Windows Git Bash:
#
#  * At a 1.2 s bound with a 400 ms tolerance: failed (1866 vs 1275 ms).
#  * At a 3.0 s bound with a 1200 ms tolerance — a 2.25 s signal — single samples
#    on an otherwise idle box gave paired deltas of +2938, +1688, +1110, -2245,
#    -837 ms. The noise EXCEEDS the signal and straddles zero, so no fixed
#    tolerance discriminates.
#  * With the interleaved-sampling machinery the other two cases use (then a
#    pooled median of five pairs), five interleaved pairs gave +3216, -2886,
#    -4427, +433, -3850 ms: a 7.6 s spread and a middle value of -2886 ms, i.e. a
#    systematic 2.9 s offset between two arms that the mechanism says should
#    match. That offset is unexplained. Setting a tolerance on a number whose
#    cause is unknown is how this case kept failing, so it is not being retuned
#    again.
#
# The cause is buffer_stdin's own startup: it spends two command-substitution
# forks resolving its timeout and slice, and a fork on this platform measured
# 93 ms to 3234 ms across four back-to-back runs — a single fork's variance
# exceeds the whole signal. The other two comparisons survive that because their
# arms differ by several seconds of real work; this one has no such margin.
#
# WHAT THE LATENCY HALF COVERED, stated plainly: a regression that removed the
# empty-slice completeness check makes an exactly-chunk-sized payload wait out
# the whole idle bound instead of one slice. Nothing about the RETURN VALUE
# changes — measured 2026-08-09 by deleting that block from hook-utils.sh,
# baseline rc=0 len=65536 in 2948 ms against mutant rc=0 len=65536 in 5823 ms —
# so an assertion on rc and content cannot see it. It was never true, though,
# that NOTHING non-temporal distinguishes the two paths, which is what this said
# when the comparison was removed: the surviving payload is identical, but
# WHETHER the completeness verdict is reached inside the read loop is not, and
# that is observable without a clock.
#
# WHAT IS COVERED BELOW, load-independently, in three parts: that the fixtures
# really are exactly chunk-sized; that a payload landing exactly on the boundary
# comes back WHOLE and with rc 0; and that the empty-slice check ENGAGES — fires
# on the FIRST idle slice — which is the part that goes red on the mutation
# above and the reason the correctness assertion alone does not stand in for the
# deleted comparison.
#
# WHAT REMAINS UNCOVERED, since one gap closing is not all of them: the LATENCY
# CONSEQUENCE itself. The engagement probe pins the verdict to the first idle
# slice, so it catches both deleting the check and moving it later, but a
# regression that spent the bound somewhere else entirely while still calling the
# check on time would pass it. That would need the wall-clock comparison this
# host cannot make.
bs_make_payload() { # $1 = exact payload length in bytes, $2 = destination file
  # `{"p":"` + pad + `"}` — 8 bytes of envelope. Built with pure parameter
  # expansion rather than a `yes | … | head -c` pipeline: the exact length is the
  # entire point of this case, and a generator whose length depends on where the
  # newline stripping happens (or on a pipeline terminating cleanly under MSYS)
  # is one that can silently produce the wrong fixture.
  local pad
  printf -v pad '%*s' "$(($1 - 8))" ''
  printf '{"p":"%s"}' "${pad// /a}" >"$2"
}
# The whole case turns on the payload being EXACTLY chunk-sized, and an off-by-a-
# few generator would quietly compare two non-boundary payloads. Assert the
# lengths first.
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
# The correctness half of the boundary edge, asserted on CONTENT so no clock is
# involved: an exactly-chunk-sized payload on a pipe that never closes must come
# back whole, with rc 0. The pipe is held open by the same handshake the timing
# cases use, so this really is the late-EOF path and not an EOF-terminated read.
bs_payload_file="$(mktemp)"
bs_rc_file="$(mktemp)"
bs_out_file="$(mktemp)"
bs_make_payload 65536 "$bs_payload_file"
{
  cat "$bs_payload_file"
  bs_hold_open
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1.2 hook::buffer_stdin >"$bs_out_file" 2>/dev/null
  echo "$?" >"$bs_rc_file"
  bs_release
}
bs_rc=$(cat "$bs_rc_file")
bs_len=$(wc -c <"$bs_out_file")
if [[ "$bs_rc" == "0" ]] && ((bs_len == 65536)); then
  ok "buffer_stdin: an exactly-chunk-sized payload on a held-open pipe returns whole (rc 0, $bs_len bytes)"
else
  fail "buffer_stdin chunk boundary: rc=$bs_rc len=$bs_len (expected rc 0, 65536 bytes)"
fi
rm -f "$bs_payload_file" "$bs_rc_file" "$bs_out_file"

# The ENGAGEMENT half, which the assertion above cannot reach: the empty-slice
# completeness check has to FIRE, and fire on the FIRST idle slice. Delete the
# block at hook-utils.sh:559 and the assertion above stays green while the helper
# burns the whole bound (2948 ms baseline against 5823 ms mutant, measured), so
# on its own it converts none of the removed comparison's coverage.
#
# The observable that separates them without a clock is WHERE the completeness
# verdict is reached. hook::json_complete is overridden to record that and then
# do the real work and return the real verdict — the same rule the two overrides
# above follow: an override may lie about a VERDICT, never skip the WORK. Here it
# does not even lie; it only writes a line before returning what jq said.
#
# Bash's dynamic scoping puts hook::buffer_stdin's own locals in scope for the
# override, which is what lets it record WHICH check called it. `chunk` is empty
# only at the empty-slice check (hook-utils.sh:559) and non-empty at the
# with-bytes one (:540), and `idle_slices` is how many idle slices had already
# been spent when the verdict landed. The pass shape is therefore exactly
# `idle=0 chunklen=0` — complete on the first idle slice, not after the bound.
#
# What each mutation does to that log: deleting the block leaves it EMPTY, since
# the trailing probe at hook-utils.sh:586 is an inline `printf | jq` and not this
# function, so the case fails. Moving the check later — an `idle_slices >= 3`
# guard, say — logs a non-zero idle count, so that fails too. Only SUCCESSFUL
# verdicts are logged, the partial buffers probed on the way in returning
# non-zero and writing nothing, which is what makes the last line the call that
# actually completed rather than merely the most recent one.
#
# If the FIFO handshake were ever unavailable, the producer's EOF would end the
# read before any slice expired and the log would come back empty — this case
# then fails LOUDLY rather than quietly asserting nothing.
#
# FRAGMENTED delivery is the one shape that does not reach the empty-slice check:
# if the payload lands in pieces, an intermediate read times out holding bytes
# and the WITH-BYTES check at hook-utils.sh:540 sees the completion first. That
# is reported as unexercised rather than passed as covered — and it is retried
# first, since it is a delivery accident and not a property of the code. Nor can
# it mask the regression, which is the reason exhausting the retries is not a
# failure: under a fragmented delivery the mutant behaves IDENTICALLY, because
# the check it deletes is only ever reached when the payload completes on an rc-0
# read. Measured 2026-08-09 by splitting the payload in half across a gap longer
# than one slice — baseline and the block-deleted mutant produced the same two
# probe entries (a FAILED verdict on the 32768-byte partial, then a successful
# one at 65536 with 32768 bytes still in `chunk`) and both returned at the same
# point. There is nothing to catch on that path, so failing there would be a
# false fail on a helper that is behaving correctly.
bs_probe_file="$(mktemp)"
bs_payload_file="$(mktemp)"
bs_rc_file="$(mktemp)"
bs_out_file="$(mktemp)"
bs_make_payload 65536 "$bs_payload_file"
# shellcheck disable=SC2016 # $1 is the overriding function's own positional, not this shell's
bs_probe_override='hook::json_complete() {
  local verdict=0
  printf "%s" "$1" | jq -e . >/dev/null 2>&1 || verdict=$?
  if ((verdict == 0)); then
    printf "idle=%s chunklen=%s\n" "${idle_slices-?}" "${#chunk}" >>"'"$bs_probe_file"'"
  fi
  return "$verdict"
}'
bs_probe_run() { # sets bs_rc, bs_len, bs_probe_last from one whole-payload run
  : >"$bs_probe_file"
  {
    cat "$bs_payload_file"
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
# Three tries, because a fragmented delivery is an accident of scheduling and not
# a property of the code — one retry usually lands the whole payload in a single
# read. Never observed to need one here (five local runs and CI all reached the
# empty-slice check first try); the retry exists so that reporting the case
# unexercised takes a host that cannot reach the path at all, not a single
# unlucky sample.
#
# EVERY attempt is classified, not just the last. Retrying a shape that is only
# ever produced by a REGRESSION would discard the evidence: a moved check yields
# `idle=<n> chunklen=0` deterministically, and if a later attempt then happened
# to fragment, a loop that only inspected its final state would report the case
# unexercised and stay green on a defect it had already seen. So a bad shape
# fails on the spot, a fragmented one is the only thing that earns a retry, and
# "fragmented on all 3" is reached only by fragmenting three times.
bs_engagement=""
for bs_attempt in 1 2 3; do
  bs_probe_run
  if [[ "$bs_rc" == "0" ]] && ((bs_len == 65536)) && [[ "$bs_probe_last" == "idle=0 chunklen=0" ]]; then
    bs_engagement=exercised
    break
  fi
  if [[ "$bs_rc" == "0" ]] && ((bs_len == 65536)) && [[ "$bs_probe_last" == idle=0\ chunklen=* ]]; then
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
  # Not a regression, and not coverage either: all three attempts arrived
  # fragmented, so the with-bytes check caught completion first and the
  # empty-slice path was never reached — by the helper, not merely by this
  # assertion, which is why this is not a failure (see above). Reported as
  # unexercised, never as covered.
  ok "buffer_stdin: chunk-boundary payload arrived fragmented on all 3 attempts (last: $bs_probe_last), so the empty-slice check was not exercised this run — correctness holds, engagement unasserted"
  ;;
*)
  fail "buffer_stdin chunk-boundary engagement: attempt $bs_attempt gave rc=$bs_rc len=$bs_len probe='$(tr '\n' ';' <"$bs_probe_file")' (expected rc 0, 65536 bytes, and a completeness verdict at idle=0 chunklen=0)"
  ;;
esac
rm -f "$bs_probe_file" "$bs_payload_file" "$bs_rc_file" "$bs_out_file"

if bs_samples 6 bs_time_stall "" "$bs_unsliced"; then
  bs_paired_verdict "buffer_stdin: stall declared near one bound, not two" \
    400 sliced unsliced
elif [[ -n "${EPOCHREALTIME:-}" ]]; then
  fail "stall timing harness produced no measurement"
else
  ok "buffer_stdin: stall overshoot not timed (EPOCHREALTIME absent, Bash < 5.0)"
fi
rm -f "$bs_release_fifo"

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

# --- hook::git_resolve_index reports a wrapper's chdir ------------------------
# A caller that scopes its git-global parsing to [gi, sub_idx) cannot see a
# relocation the wrapper performs, so the resolver — the only parser that knows
# which wrapper options take a value — reports it. `env -C DIR` moves git; the
# `-C` in `env -u -C git` is -u's operand and moves nothing.
# resolve_dirs_are <desc> <expected-dirs-joined-by-|> <argv...>
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
# env clusters short options, so a valueless flag can carry the chdir in the same
# word: -vC is --debug plus --chdir, which no exact -C match sees.
resolve_dirs_are "env -vC DIR (clustered) reports the chdir" "other" env -vC other git commit
resolve_dirs_are "env -iC DIR (clustered) reports the chdir" "other" env -iC other git commit
# -u consumes the NEXT word as a variable name, so this -C is env's operand and
# git never moves. Reporting it here is the bypass this whole boundary exists for.
resolve_dirs_are "env -u swallows -C, so no chdir is reported" "" env -u -C git commit
resolve_dirs_are "env -uNAME (attached) leaves a later -C as env's chdir" "other" env -uFOO -C other git commit
# One env keeps --chdir in a single slot, so a repeat is last-wins, not cumulative.
resolve_dirs_are "repeated env -C is last-wins within one env" "second" env -C first -C second git commit
# Operands and the option terminator must not be read as options.
resolve_dirs_are "env NAME=value operand carries no chdir" "" env FOO=bar git commit
resolve_dirs_are "env -- ends option parsing" "other" env -C other -- git commit
resolve_dirs_are "a chdir BEFORE the operand still counts" "other" env -C other FOO=1 git commit
# A NAME=value operand ends option parsing too, so `env FOO=1 -C dir git …` makes
# env look for a command literally named `-C` and fail — nothing runs, and the
# resolver reports no git rather than recording a chdir env never performs.
if hook::git_resolve_index env FOO=1 -C other git commit; then
  fail "a NAME=value operand ends option parsing: resolved git at $HOOK_GIT_RESOLVED_GI, expected none"
else
  ok "a NAME=value operand ends option parsing, so no git resolves"
fi
# sudo's chdir is -D/--chdir; its -C is close-from and takes a value of its own.
resolve_dirs_are "sudo -D DIR reports the chdir" "other" sudo -D other git commit
resolve_dirs_are "sudo --chdir=DIR reports the chdir" "other" sudo --chdir=other git commit
resolve_dirs_are "sudo -C fd is not a chdir" "" sudo -C 3 git commit
# Nested wrappers each contribute, in execution order, for the caller to compose.
resolve_dirs_are "nested wrappers report both chdirs in order" "a|b" env -C a sudo -D b git commit
# `-S` exists so a shebang line can pass OPTIONS to env (`#!/usr/bin/env -S -i
# prog`), so the split words are env's own arguments and parsing must resume
# inside env's option loop. Resuming at the command dispatcher read a leading
# option in the split string as the COMMAND NAME and abandoned the segment
# entirely — the resolver reported no git, and every guard skipped the command.
resolve_dirs_are "env -S splices a chdir that belongs to env" "other" env -S '-C other git commit'
resolve_dirs_are "env --split-string= splices a chdir that belongs to env" "other" env --split-string='-C other git commit'
resolve_dirs_are "env -S with an attached operand splices the chdir" "other" env "-S-C other git commit"
resolve_dirs_are "env -S with no leading option still resolves git" "" env -S 'git commit'
# One env, one chdir slot: a -C inside the split string is last-wins against an
# earlier one outside it, not cumulative.
resolve_dirs_are "env -C first -S '-C second …' is last-wins in the one slot" "second" env -C first -S '-C second git commit'
# A valueless clustered option inside the split string must not swallow the chdir.
resolve_dirs_are "env -S '-v -C DIR git …' keeps the chdir" "other" env -S '-v -C other git commit'
# Termination: a self-referential -S consumes itself rather than looping.
if hook::git_resolve_index env -S '-S -S'; then
  fail "env -S '-S -S' should resolve no git, resolved at $HOOK_GIT_RESOLVED_GI"
else
  ok "a self-referential env -S terminates and resolves no git"
fi

# --- resolve_read_slice: shell fixed-point division ---------------------------
# The slice is produced by shell arithmetic rather than an awk spawn, and its
# printed form is load-bearing twice over: it is fed to `read -t` and it is
# re-matched against ^[0-9]+\.[0-9]+$ / ^0+\.0+$ by resolve_read_slice itself.
# A format regression would not fail loudly — it would silently degrade every
# hook to the unsliced bound.
slice_is() {
  local label="$1" input="$2" want="$3" got
  got=$(hook::resolve_read_slice "$input")
  if [[ "$got" == "$want" ]]; then
    ok "resolve_read_slice: $label"
  else
    fail "resolve_read_slice $label: got '$got', want '$want'"
  fi
}
slice_is "the default bound splits into four 500 ms slices" 2 "0.500 4"
slice_is "an integer bound divides exactly" 10 "2.500 4"
slice_is "a fractional bound keeps three decimals" 0.5 "0.125 4"
slice_is "a sub-slice bound still yields a usable slice" 0.004 "0.001 4"
# A quotient that formats as 0.000 is unusable as a `read -t` value, so the
# helper must degrade to the unsliced form rather than emit it.
slice_is "a zero bound falls back to the unsliced form" 0.000 "0.000 1"
# Anything the numeric pattern rejects degrades the same way — the branch the
# awk-failure path used to cover.
slice_is "a non-numeric bound falls back to the unsliced form" abc "abc 1"

# --- jq_fields: one jq process, index-parallel results ------------------------
# The newline and CR are JSON escapes, not raw control bytes — raw ones are
# invalid inside a JSON string and jq would reject the whole payload.
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

# The reason this helper uses `// ""` and not `// empty`: a dropped field would
# shift every later value onto the wrong index, so an absent field must hold its
# slot as the empty string.
if hook::jq_fields "$jf_input" '.tool_input.file_path' '.tool_name'; then
  if [[ "${#HOOK_JQ_FIELDS[@]}" -eq 2 && -z "${HOOK_JQ_FIELDS[0]}" && "${HOOK_JQ_FIELDS[1]}" == "Bash" ]]; then
    ok "jq_fields: an absent field keeps its slot instead of shifting the rest"
  else
    fail "jq_fields absent-field slot: got (${#HOOK_JQ_FIELDS[@]}) '${HOOK_JQ_FIELDS[0]-}' / '${HOOK_JQ_FIELDS[1]-}'"
  fi
else
  fail "jq_fields returned $? when a requested field was absent"
fi

# A payload jq cannot parse yields no values at all — never a partial set the
# caller could mistake for a complete read.
if hook::jq_fields 'not json at all' '.tool_name' '.session_id'; then
  fail "jq_fields accepted an unparsable payload"
elif ((${#HOOK_JQ_FIELDS[@]} == 0)); then
  ok "jq_fields: an unparsable payload returns non-zero and leaves no values"
else
  fail "jq_fields left ${#HOOK_JQ_FIELDS[@]} values after an unparsable payload"
fi

if hook::jq_fields "$jf_input"; then
  fail "jq_fields accepted a call with no filters"
else
  ok "jq_fields: a call with no filters returns non-zero"
fi

# A JSON string may legitimately encode a NUL, and a Write/Edit content field
# does reach this helper. The NUL delimiter is only safe because every value is
# NUL-stripped jq-side FIRST: without that strip jq emitted the raw byte, the
# read split one value into two, the cardinality check failed, and every
# caller's `|| exit 0` skipped its guard outright — a fail-open the per-field
# command substitution this helper replaced never had, because `$( )` dropped
# the NUL and kept the rest of the value. The value after the NUL must survive.
# The payload is built with jq (`[0] | implode`) so no literal escape sequence
# for the byte lives in this file's source.
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

# Non-string JSON values are stringified rather than dropped, so a numeric or
# null field cannot desynchronize the indexes either.
if hook::jq_fields '{"a":5,"b":null}' '.a' '.b' &&
  [[ "${HOOK_JQ_FIELDS[0]}" == "5" && -z "${HOOK_JQ_FIELDS[1]}" ]]; then
  ok "jq_fields: a number stringifies and a null becomes the empty string"
else
  fail "jq_fields non-string handling: got '${HOOK_JQ_FIELDS[0]-}' / '${HOOK_JQ_FIELDS[1]-}'"
fi

# --- jq_fields: a NUL in a value must not split the frame (#2122) -------------
# The separator was drawn from the same byte space as the values it separates,
# so a JSON NUL escape inside a value split that value in two, failed the
# cardinality check, and returned 1 — which every guardrail caller spells
# `|| exit 0`, i.e. ALLOW. jq now STRIPS every NUL out of each value, so the
# separator cannot occur inside one and the record count no longer depends on
# what a parseable payload holds. Stripping is not a claim about how a NUL would
# execute — it SPLICES the bytes either side into a token the payload never
# carried contiguously — which is exactly why the NUL itself is reported in
# HOOK_JQ_FIELDS_NUL: only the caller can own the verdict, and the two guards
# refuse on the flag rather than match the spliced value.
#
# A NUL cannot live in a shell variable, so the payload is built inside jq:
# `[0] | implode` is the one-character NUL string (jq re-emits it as a NUL
# escape on the wire), and `[92] | implode` is a backslash — which keeps both
# a raw NUL and an escape out of this file's own source.
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

# The point of the fix is what the CALLER sees. A NUL used to make the helper
# return non-zero, which every guardrail turns into an allow; now it returns
# success and reports the NUL, so the caller can fail CLOSED on its own terms.
if hook::jq_fields "$jf_nul" '.tool_input.command'; then
  if [[ "$HOOK_JQ_FIELDS_NUL" == 1 ]]; then
    ok "jq_fields: a NUL is reported to the caller instead of returning its fail-open code"
  else
    fail "jq_fields HOOK_JQ_FIELDS_NUL: expected 1 on a NUL-bearing payload, got '$HOOK_JQ_FIELDS_NUL'"
  fi
else
  fail "jq_fields returned $? on a NUL-bearing payload — callers spell that ALLOW"
fi

# A NUL only the LAST filter carries must still raise the flag — the report is
# over every requested value, not just the first.
if hook::jq_fields "$jf_nul" '.tool_name' '.only_nul' && [[ "$HOOK_JQ_FIELDS_NUL" == 1 ]]; then
  ok "jq_fields: a NUL in any requested field raises the flag"
else
  fail "jq_fields flag on a trailing NUL field: got '$HOOK_JQ_FIELDS_NUL'"
fi

# A leading NUL KEEPS its text under stripping — it is the splice, not an empty
# value, that a command guard has to survive. `--no-verify<NUL>x` arrives as the
# single token `--no-verifyx`, which no matcher recognizes, so a caller reading
# only the value would allow it. The flag is the only thing that separates it
# from a clean payload, which is why the two guards refuse on the flag instead of
# matching the value.
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

# A value that is NOTHING BUT NUL bytes strips to empty, and is then
# indistinguishable from an absent field. That case — not a leading NUL — is why
# both guards consult the flag AHEAD of their empty-command skip.
jf_allnul=$(jq -n '{tool_input: {command: (([0] | implode) + ([0] | implode))}}')
if hook::jq_fields "$jf_allnul" '.tool_input.command' &&
  [[ -z "${HOOK_JQ_FIELDS[0]}" && "$HOOK_JQ_FIELDS_NUL" == 1 ]]; then
  ok "jq_fields: an all-NUL value strips to empty and still raises the flag"
else
  fail "jq_fields all-NUL: got '${HOOK_JQ_FIELDS[0]-}' flag '$HOOK_JQ_FIELDS_NUL'"
fi

# Set on EVERY call, not only when a NUL is present: a caller that never resets
# it must not inherit a stale 1 from an earlier invocation. Both assertions run
# the NUL payload FIRST on purpose — a single call cannot observe a stale value
# however it is written.
hook::jq_fields "$jf_nul" '.tool_input.command'
if hook::jq_fields "$jf_input" '.tool_name' && [[ "$HOOK_JQ_FIELDS_NUL" == 0 ]]; then
  ok "jq_fields: a clean payload clears the flag rather than leaving it stale"
else
  fail "jq_fields stale flag: expected 0 after a clean payload, got '$HOOK_JQ_FIELDS_NUL'"
fi

# The early returns — no filters, and a host without jq — fire before any NUL
# could be observed, so the flag has to be cleared in the same unconditional
# block that resets the array rather than on detection. In a guard a stale 1
# would block a clean payload on the strength of an earlier one.
hook::jq_fields "$jf_nul" '.tool_input.command'
hook::jq_fields "$jf_nul" || true
if [[ "$HOOK_JQ_FIELDS_NUL" == 0 ]]; then
  ok "jq_fields: an early return clears the flag instead of leaking the previous call's"
else
  fail "jq_fields early-return flag: expected 0, got '$HOOK_JQ_FIELDS_NUL'"
fi

# --- Test 20: hook::is_enabled / hook::check_enabled --------------------------
# `check_enabled` exits the process when a plugin is gated off, so a case cannot
# be asserted in-process: each runs in a child bash that sources the lib and
# prints a sentinel only if the gate let it through. Absence of the sentinel IS
# the "skipped" signal. Each probe unsets the control variable first so an
# ambient value in the test runner's own environment cannot mask a regression.
#
# Scope note: this gate reads ONLY the plugin's own userConfig mirror. Turning
# the whole fleet off is Claude Code's job (`--safe-mode`, `disableAllHooks`,
# `claude plugin disable`), not this library's — a second fleet-wide switch here
# would be a competing source of truth for the same question.
ce_probe() {
  # ce_probe <RUN|SKIP> <description> [VAR=VALUE ...]
  local want="$1" desc="$2"
  shift 2
  local got
  got=$(
    # shellcheck disable=SC2016  # $0 must NOT expand here: it is the child bash's
    # own positional, bound to the library path passed after the -c string.
    env -u CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED \
      "$@" bash -c 'source "$0"; hook::check_enabled "RATE_LIMIT_GUARD"; printf RUN' \
      "$HOOK_DIR/hook-utils.sh" 2>/dev/null
  )
  got="${got:-SKIP}"
  if [[ "$got" == "$want" ]]; then
    ok "check_enabled: $desc"
  else
    fail "check_enabled: $desc — got '$got', want '$want'"
  fi
}

# The default must not move: every existing installation leaves this unset, so a
# regression here silently changes behavior for every user of the marketplace.
ce_probe RUN "unset stays enabled (backward compatibility)"
ce_probe RUN "explicit true" CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED=true
ce_probe SKIP "explicit false" CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED=false
# Anything that is not exactly "true" is off — a typo must not read as enabled.
ce_probe SKIP "a non-boolean value is not 'true'" CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED=yes
# An EMPTY value is treated as unset, not as false: `${var:-true}` falls back to
# the default. This is long-standing behavior, asserted here so a future change
# to the parameter expansion (`:-` to `-`) can't flip it silently. It matters
# because Claude Code exports every declared userConfig option to the hook
# environment, so an option the user never answered arrives as an empty string —
# and that must mean "default", not "disabled".
ce_probe RUN "empty value falls back to the default (treated as unset)" \
  CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED=

# hook::is_enabled is the predicate form: same answer, but it RETURNS instead of
# exiting. The statusline tee depends on this — it wraps the user's real
# statusline, so an exit would blank the status line instead of just skipping
# the tee's own write.
ie_probe() {
  local want="$1" desc="$2"
  shift 2
  local got
  got=$(
    # shellcheck disable=SC2016  # $0 must NOT expand here: it is the child bash's
    # own positional, bound to the library path passed after the -c string.
    env -u CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED \
      "$@" bash -c 'source "$0"
        if hook::is_enabled "RATE_LIMIT_GUARD"; then printf ENABLED; else printf DISABLED; fi
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
  CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED=true
# The critical one: a disabled answer must NOT terminate the caller.
ie_probe "DISABLED+SURVIVED" "explicit false returns false WITHOUT exiting" \
  CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED=false

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
