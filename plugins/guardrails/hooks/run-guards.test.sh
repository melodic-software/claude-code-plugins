#!/usr/bin/env bash
# Contract tests for hooks/run-guards.sh, the one-process dispatcher that runs
# several guards for one hook event. The guards' own decisions are covered by
# their own *.test.sh; this file covers what the dispatcher owns: stdin read
# once and re-served with the same rc, jq answered from one cache with a
# byte-identical fallback, every guard run to completion, exit aggregation,
# and the merge of several stdout documents into one.
#
# Stub guards isolate each of those mechanics, but a mechanic asserted only
# against a stub is asserted against a stand-in for the thing it serves, so the
# merge, the no-jq arbitration and the exit aggregation are each also driven
# with SHIPPED guards, whose documents this file does not write. The guards'
# own decisions stay covered by their own *.test.sh, which now assert those
# decisions on both paths (`expect_both` in guardrails-test-helpers.sh).
#
# The stub guard bodies below are single-quoted on purpose: they are written
# verbatim into stub scripts, so their `$` must not expand here.
# test-scope: plugins/guardrails/hooks/*.sh
# shellcheck disable=SC2016
set -uo pipefail

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/run-guards-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="$HOOK_DIR/run-guards.sh"
# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free

export CLAUDE_PLUGIN_ROOT="$HOOK_DIR/.."
export CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for these tests" >&2
  exit 1
fi

# Git Bash rewrites an argument that is entirely a POSIX path before a native
# jq sees it. Fixture files are created at the bash spelling, so payloads must
# carry it unrewritten or the verifiers never find the file and never call git
# (#4527). The suppression is scoped to this suite's own jq calls, never
# exported: git.exe and the guards under test would inherit it and fail to
# open a POSIX /tmp/... repo. The no-jq probe runs the dispatcher in a child
# bash, which does not inherit the function. The one path jq must open itself,
# hooks.json, goes through cygpath -m when it exists, because a native jq
# cannot open a POSIX /c/... spelling.
if declare -F jq >/dev/null; then
  jq() { MSYS_NO_PATHCONV=1 command jq --binary "$@"; }
fi
HOOKS_JSON="$HOOK_DIR/hooks.json"
if command -v cygpath >/dev/null 2>&1; then HOOKS_JSON=$(cygpath -m "$HOOKS_JSON"); fi

# Stub guards. Each one sources the real library exactly as a shipped guard
# does, so the dispatcher's overrides are exercised through the same seam.
stub() {
  local name="$1" body="$2"
  {
    printf '#!/usr/bin/env bash\nset -uo pipefail\nsource "%s/hook-utils.sh"\n' "$HOOK_DIR"
    printf '%s\n' "$body"
  } >"$TEST_TMPDIR/$name"
  chmod +x "$TEST_TMPDIR/$name"
}
SEEN="$TEST_TMPDIR/seen"
# The stub bodies are written verbatim into the stub scripts, so the `$` in them
# must NOT expand here.
# shellcheck disable=SC2016
stub allow.sh 'hook::buffer_stdin_to INPUT || { rc=$?; ((rc == 2)) && exit 2; exit 0; }
hook::jq_fields "$INPUT" ".tool_input.command" ".tool_name" || exit 0
printf "%s\n" "${HOOK_JQ_FIELDS[@]}" >>"'"$SEEN"'"
exit 0'
stub dest.sh 'hook::buffer_stdin_to dest || { rc=$?; ((rc == 2)) && exit 2; exit 0; }
printf "%s\n" "$dest" >>"'"$SEEN"'"
exit 0'
stub block.sh 'echo "BLOCKED: stub" >&2; exit 2'
stub ctx1.sh 'hook::emit_channels PreToolUse "ctx one" ""; exit 0'
stub ctx2.sh 'hook::emit_channels PreToolUse "ctx two" "sys two"; exit 0'
stub crash.sh 'exit 3'
stub nul.sh 'hook::buffer_stdin_to INPUT || exit 0
hook::jq_fields "$INPUT" ".tool_input.command" || exit 0
printf "nul=%s cmd=%s\n" "$HOOK_JQ_FIELDS_NUL" "$HOOK_JQ_FIELDS" >>"'"$SEEN"'"'
stub miss.sh 'hook::buffer_stdin_to INPUT || exit 0
hook::jq_fields "$INPUT" ".session_id" ".tool_name" || exit 0
printf "%s\n" "${HOOK_JQ_FIELDS[@]}" >>"'"$SEEN"'"'
stub lib.sh 'printf "ps=%s\n" "${_GUARDRAILS_PS_COMMAND_LOADED:-unset}" >>"'"$SEEN"'"'
stub dirname.sh 'printf "%s %s\n" "$(type -t dirname)" "$(dirname /foo)" >>"'"$SEEN"'"'
# Raw documents (no library call) so the no-jq merge fallback is exercised on
# the shapes it has to recognize, not on what hook::emit_channels happens to build.
stub deny.sh 'hook::emit_document "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"stub deny\"}}"'
stub ask.sh 'hook::emit_document "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\": \"ask\"}}"'

PAYLOAD=$(jq -n '{session_id:"s-1",tool_name:"Bash",cwd:"/x",tool_input:{command:"git status --short"}}')

# run <stdin-string> [--lib <path>]... <guard>... -> OUT, ERR, RC.
#
# The invocation itself is the shared driver's (guardrails-test-helpers.sh), so
# this suite and every guard suite reach the dispatcher through one code path;
# what is left here is the translation from this suite's positional guard list
# to the driver's `--hook` / `--also` / `--lib`.
run() {
  local input="$1"
  shift
  : >"$SEEN"
  local -a opts=()
  local first=1
  while (($#)); do
    case "$1" in
    --lib)
      opts+=(--lib "$2")
      shift 2
      ;;
    *)
      if ((first)); then
        opts+=(--hook "$1")
        first=0
      else
        opts+=(--also "$1")
      fi
      shift
      ;;
    esac
  done
  guard_invoke --via dispatched --payload "$input" ${opts[@]+"${opts[@]}"}
  OUT="$GUARD_OUT"
  ERR="$GUARD_ERR"
  RC="$GUARD_RC"
}

# --- benign payload, one allowing guard ---------------------------------------
run "$PAYLOAD" "$TEST_TMPDIR/allow.sh"
assert_exit "allow-only exits 0" 0 "$RC"
assert_silent "allow-only prints nothing" "$OUT$ERR"
assert_eq "guard read its fields from the shared cache" \
  $'git status --short\nBash' "$(cat "$SEEN")"

# Dest named `dest` must still receive the payload through the dispatcher
# override (an unprefixed local dest would swallow the printf -v).
run "$PAYLOAD" "$TEST_TMPDIR/dest.sh"
assert_exit "dest-named dest exits 0" 0 "$RC"
assert_contains "dest-named dest received the payload" "$(cat "$SEEN")" 'tool_name'

# --- a block does not stop the later guards, and wins the exit code ----------
run "$PAYLOAD" "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "block wins the exit code" 2 "$RC"
assert_contains "block reason reaches stderr" "$ERR" "BLOCKED: stub"
assert_eq "the guard after the block still ran" $'git status --short\nBash' "$(cat "$SEEN")"

# --- exit aggregation: a non-block failure surfaces, 2 still dominates ------
run "$PAYLOAD" "$TEST_TMPDIR/crash.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "highest non-block code surfaces" 3 "$RC"
run "$PAYLOAD" "$TEST_TMPDIR/crash.sh" "$TEST_TMPDIR/block.sh"
assert_exit "2 dominates a higher non-block code" 2 "$RC"

# --- stdout: one emitter passes through verbatim -----------------------------
standalone=$(bash "$TEST_TMPDIR/ctx1.sh" <<<"$PAYLOAD")
run "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh"
assert_eq "single emitter is passed through verbatim" "$standalone" "$OUT"

# --- stdout: several emitters merge into ONE document ------------------------
run "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/ctx2.sh"
assert_exit "merge run exits 0" 0 "$RC"
assert_eq "merged output is exactly one JSON document" "1" "$(jq -s 'length' <<<"$OUT")"
merged_ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")
merged_ctx="${merged_ctx//$'\r'/}" # the Windows jq build writes CRLF
assert_eq "merged additionalContext carries both guards, in order" $'ctx one\n\nctx two' "$merged_ctx"
assert_eq "merged hookEventName kept" "PreToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$OUT")"
assert_eq "merged systemMessage carries the one guard that set it" "sys two" "$(jq -r '.systemMessage' <<<"$OUT")"

# --- stdin posture is re-served, not re-read ---------------------------------
run "" "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/block.sh"
assert_exit "empty stdin: every guard's empty-stdin skip, taken once" 0 "$RC"
assert_silent "empty stdin prints nothing" "$OUT$ERR"
run "not json" "$TEST_TMPDIR/allow.sh"
assert_exit "malformed stdin: a fail-closed guard's rc-2 path is reached" 2 "$RC"
assert_contains "malformed stdin names the reason once" "$ERR" "not valid JSON"
assert_eq "malformed-stdin reason printed exactly once" "1" "$(grep -c 'not valid JSON' <<<"$ERR")"

# A payload cut short at EOF — a well-formed JSON prefix the pipe CLOSED on
# (`<<<` closes it) — is a transport fault, not a verdict on the command. The
# dispatcher takes it once as a loud allow: exit 0, the notice on
# systemMessage and stderr, and no guard runs (block.sh would have exited 2
# had it run). That "no guard ran" is EOF-specific; the stall case below is
# the other half of the pin.
CUT_PREFIX='{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify'
run "$CUT_PREFIX" "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/block.sh"
assert_exit "cut-short stdin (early EOF): loud allow, taken once" 0 "$RC"
assert_contains "cut-short stdin (early EOF): the lib diagnostic names the cause" "$ERR" "cut short"
assert_absent "cut-short stdin (early EOF): nothing is BLOCKED" "$ERR" "BLOCKED"
assert_eq "cut-short stdin (early EOF): exactly one JSON document on stdout" "1" "$(jq -s 'length' <<<"$OUT")"
assert_contains "cut-short stdin (early EOF): systemMessage carries the notice" "$(jq -r '.systemMessage' <<<"$OUT")" "not evaluated"
assert_eq "cut-short stdin (early EOF): notice printed exactly once" "1" "$(grep -c 'not evaluated' <<<"$ERR")"
assert_eq "cut-short stdin (early EOF): no guard ran" "" "$(cat "$SEEN")"
# The SAME prefix with the pipe HELD OPEN past the idle bound is a stall, and
# a stall is rc 2 by decision: the exit above precedes every guard, so an
# allow on a stall would skip all of them at once. The dispatcher must fall
# through and the guards must RUN: block.sh's own BLOCKED line on stderr is
# the proof it was sourced, and the lib's timed-out line is the reason. The
# hold is a FIFO handshake released only after the dispatcher exits.
STALL_FIFO="$TEST_TMPDIR/stall.fifo"
if mkfifo "$STALL_FIFO" 2>/dev/null; then
  stall_hold() { read -r _ <"$STALL_FIFO"; }
  stall_release() { : >"$STALL_FIFO"; }
else
  stall_hold() { sleep 30; }
  stall_release() { :; }
fi
: >"$SEEN"
RC=0
OUT=$({
  printf '%s' "$CUT_PREFIX"
  stall_hold
} | {
  CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=0.4 bash "$DISPATCH" "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/block.sh" 2>"$TEST_TMPDIR/err"
  echo "$?" >"$TEST_TMPDIR/stall.rc"
  stall_release
}) || true
RC=$(cat "$TEST_TMPDIR/stall.rc")
ERR=$(cat "$TEST_TMPDIR/err")
assert_exit "stalled stdin: the guards ran and the block won the exit code" 2 "$RC"
assert_contains "stalled stdin: the lib names the stall, not a cut-short" "$ERR" "timed out before a complete JSON payload"
assert_absent "stalled stdin: no cut-short notice" "$ERR" "not evaluated"
assert_absent "stalled stdin: no cut-short diagnostic" "$ERR" "cut short"
assert_contains "stalled stdin: block.sh was sourced (its BLOCKED line is on stderr)" "$ERR" "BLOCKED: stub"
assert_eq "stalled stdin: the notice-only exit was not taken (no JSON document on stdout)" "0" "$(jq -s 'length' <<<"$OUT")"

# --- jq cache: a NUL-bearing payload bypasses the cache ----------------------
nul_payload=$(jq -n '{tool_name:"Bash",tool_input:{command:("git " + ([0] | implode) + "x")}}')
run "$nul_payload" "$TEST_TMPDIR/nul.sh"
assert_eq "NUL flag reaches the guard through the real jq path" "nul=1 cmd=git x" "$(cat "$SEEN")"

# --- jq cache: an un-primed filter falls through to the library --------------
run "$PAYLOAD" "$TEST_TMPDIR/miss.sh"
assert_eq "cache miss serves the right values" $'s-1\nBash' "$(cat "$SEEN")"

# --- --lib preloads a shared library once, and only on PowerShell ------------
run "$PAYLOAD" --lib lib/powershell/ps-command.sh "$TEST_TMPDIR/lib.sh"
assert_eq "--lib is skipped on a Bash payload" "ps=unset" "$(cat "$SEEN")"
PWSH_PAYLOAD=$(jq -n '{session_id:"s-1",tool_name:"PowerShell",cwd:"/x",tool_input:{command:"git status --short"}}')
run "$PWSH_PAYLOAD" --lib lib/powershell/ps-command.sh "$TEST_TMPDIR/lib.sh"
assert_eq "--lib library is loaded on a PowerShell payload" "ps=1" "$(cat "$SEEN")"

# --- a dispatched guard sees the real dirname, not a dispatcher shadow -------
run "$PAYLOAD" "$TEST_TMPDIR/dirname.sh"
assert_eq "dirname inside a dispatched guard is the external command" "file /" "$(cat "$SEEN")"

# --- relative and bare BASH_SOURCE still locate hook-utils --------------------
# Production always invokes with an absolute path, so the `cd && pwd` arm in
# run-guards.sh and the `_HOOK_SELF=.` fallback were unhit by the rest of this
# suite. `./run-guards.sh` makes `${BASH_SOURCE[0]%/*}` answer `.` (a relative
# dir); a bare filename makes the strip a no-op and takes the `=` fallback.
# Both must still source the sibling library and serve the jq cache.
# The spelling under test is the dispatcher path the driver invokes, so it is
# passed by overriding GUARD_DISPATCH for this call's dynamic extent.
run_from_hooks_dir() {
  local GUARD_DISPATCH="$1"
  shift
  : >"$SEEN"
  guard_invoke --via dispatched --payload "$PAYLOAD" --chdir "$HOOK_DIR" --hook "$1"
  OUT="$GUARD_OUT"
  ERR="$GUARD_ERR"
  RC="$GUARD_RC"
}
run_from_hooks_dir ./run-guards.sh "$TEST_TMPDIR/allow.sh"
assert_exit "relative ./run-guards.sh exits 0" 0 "$RC"
assert_eq "relative ./run-guards.sh still serves the cache" \
  $'git status --short\nBash' "$(cat "$SEEN")"
run_from_hooks_dir run-guards.sh "$TEST_TMPDIR/allow.sh"
assert_exit "bare run-guards.sh exits 0" 0 "$RC"
assert_eq "bare run-guards.sh still serves the cache" \
  $'git status --short\nBash' "$(cat "$SEEN")"
bare_guard_rc=0
(cd "$HOOK_DIR" && bash block-no-verify.sh <<<"$PAYLOAD" >/dev/null) || bare_guard_rc=$?
assert_exit "bare block-no-verify.sh from hooks/ exits 0" 0 "$bare_guard_rc"

# --- benign Bash lane: no exec and no fork on the dispatched hot path ---------
# 0.32.6: every always-on Bash guard used `source "$(dirname …)/hook-utils.sh"`
# and the dispatcher copied hook::jq_fields through sed. Those were 7 dirname
# execs plus one sed on a benign `git status --short` (flag-commit-pr-skill-bypass
# is default-off and exits before source). The one jq that remained went with
# the library's builtin field parser. PATH shims count execs; function forks
# are invisible to them, which is the same instrument as spawn-census.sh, so
# the fork count is pinned separately below through BASHPID in the xtrace.
SHIM="$TEST_TMPDIR/spawn-shim"
mkdir -p "$SHIM"
SPAWN_LOG="$SHIM/spawns.log"
for tool in dirname sed jq; do
  real=$(type -P "$tool")
  if [[ -z "$real" ]]; then
    bad "need $tool on PATH to pin its absence from the dispatcher"
    break
  fi
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q >>%q\nexec %q "$@"\n' "$tool" "$SPAWN_LOG" "$real" >"$SHIM/$tool"
  chmod +x "$SHIM/$tool"
done
if [[ -x "$SHIM/dirname" && -x "$SHIM/sed" && -x "$SHIM/jq" ]]; then
  : >"$SPAWN_LOG"
  PATH="$SHIM:$PATH" bash "$DISPATCH" --lib lib/powershell/ps-command.sh \
    block-no-verify.sh block-dangerous-git.sh block-hook-bypass.sh \
    flag-commit-pr-skill-bypass.sh block-noncanonical-commit.sh \
    block-convention-violation.sh block-windows-drive-tmp.sh \
    block-exported-msys-pathconv.sh <<<"$PAYLOAD" >/dev/null
  assert_eq "benign Bash dispatcher spends no jq, dirname or sed" "" "$(cat "$SPAWN_LOG")"
fi
DISPATCH_XTRACE=$(PS4='+PID=$BASHPID ' bash -x "$DISPATCH" --lib lib/powershell/ps-command.sh \
  block-no-verify.sh block-dangerous-git.sh block-hook-bypass.sh \
  flag-commit-pr-skill-bypass.sh block-noncanonical-commit.sh \
  block-convention-violation.sh block-windows-drive-tmp.sh \
  block-exported-msys-pathconv.sh <<<"$PAYLOAD" 2>&1 >/dev/null) || true
assert_absent "benign Bash dispatcher never sources ps-command.sh" \
  "$DISPATCH_XTRACE" "ps-command.sh"
# Every traced command ran under ONE BASHPID: no guard ran in a subshell, and
# no helper on the path forked for a capture. Every distinct PID in the trace
# is a process creation on Windows Git Bash.
assert_eq "benign Bash dispatcher forks no subshell (one BASHPID in the xtrace)" \
  "1" "$(grep -o 'PID=[0-9]*' <<<"$DISPATCH_XTRACE" | sort -u | wc -l | tr -d ' ')"
# --- PostToolUse verifiers: one path read, one root, one unprimed jq ------------
# The three verifiers each read the file path and the repository root, and two
# of them ask for the unprimed `replace_all` filter. Through the dispatcher the
# path is resolved once (one realpath, none on Linux), the root once (one git), and the jq
# that answers skill-reference-verify's unprimed filters also answers
# stale-path-verify's.
PV_REPO="$TEST_TMPDIR/pv-repo"
mkdir -p "$PV_REPO"
git -C "$PV_REPO" init -q
printf '# Doc\n\nSee `docs/a.md`.\n' >"$PV_REPO/doc.md"
PV_PAYLOAD=$(jq -cn --arg f "$PV_REPO/doc.md" \
  '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"Doc",new_string:"See `docs/a.md` again",replace_all:false},
    tool_response:{structuredPatch:[{lines:["+See `docs/a.md` again"]}]}}')
if [[ -x "$SHIM/jq" ]]; then
  printf '#!/usr/bin/env bash\nprintf "realpath\\n" >>%q\nexec %q "$@"\n' \
    "$SPAWN_LOG" "$(type -P realpath)" >"$SHIM/realpath"
  # git logs its arguments: stale-path-verify's own ls-files and log are its work, not a root read.
  printf '#!/usr/bin/env bash\nprintf "git %%s\\n" "$*" >>%q\nexec %q "$@"\n' \
    "$SPAWN_LOG" "$(type -P git)" >"$SHIM/git"
  # Git Bash resolves `git` to `git.exe` via PATHEXT. A shim named only `git`
  # is skipped and the rev-parse count stays 0 (#4527).
  cp "$SHIM/git" "$SHIM/git.exe"
  chmod +x "$SHIM/realpath" "$SHIM/git" "$SHIM/git.exe"
  : >"$SPAWN_LOG"
  PATH="$SHIM:$PATH" CLAUDE_PROJECT_DIR="$PV_REPO" bash "$DISPATCH" \
    cli-flag-verify.sh skill-reference-verify.sh stale-path-verify.sh <<<"$PV_PAYLOAD" >/dev/null 2>&1
  # Outside a marketplace repo skill-reference-verify stops at its plugins gate
  # before its payload read, and the builtin parser answers stale-path-verify's
  # `replace_all`: no jq at all.
  assert_eq "post-verify dispatcher: no jq outside a marketplace repo" \
    "0" "$(grep -cx jq "$SPAWN_LOG")"
  # Linux reads the physical paths with `cd -P` (hook::_physical_builtin_to), so no realpath runs there.
  want_realpath=1
  [[ "$OSTYPE" == linux* ]] && want_realpath=0
  assert_eq "post-verify dispatcher: $want_realpath realpath for the three path reads" \
    "$want_realpath" "$(grep -cx realpath "$SPAWN_LOG")"
  assert_eq "post-verify dispatcher: one git rev-parse for the three root reads" \
    "1" "$(grep -c 'rev-parse --show-toplevel' "$SPAWN_LOG")"
  # Inside one, skill-reference-verify reads structuredPatch with jq, and that
  # one jq also answers stale-path-verify's `replace_all` from the cache.
  mkdir -p "$PV_REPO/plugins/p/.claude-plugin"
  printf '{"name":"p"}\n' >"$PV_REPO/plugins/p/.claude-plugin/plugin.json"
  : >"$SPAWN_LOG"
  PATH="$SHIM:$PATH" CLAUDE_PROJECT_DIR="$PV_REPO" bash "$DISPATCH" \
    cli-flag-verify.sh skill-reference-verify.sh stale-path-verify.sh <<<"$PV_PAYLOAD" >/dev/null 2>&1
  assert_eq "post-verify dispatcher: one jq for the unprimed filters of both guards in a marketplace repo" \
    "1" "$(grep -cx jq "$SPAWN_LOG")"
  rm -f "$SHIM/realpath" "$SHIM/git" "$SHIM/git.exe"
fi

DISPATCH_SRC=$(cat "$DISPATCH")
assert_absent "dispatcher does not copy the library's jq_fields (the lib names its uncached form)" \
  "$DISPATCH_SRC" 'declare -f'
assert_absent "dispatcher sources no guard in a command substitution" \
  "$DISPATCH_SRC" '$(source'
for g in block-no-verify block-dangerous-git block-hook-bypass \
  flag-commit-pr-skill-bypass block-noncanonical-commit \
  block-convention-violation block-windows-drive-tmp block-exported-msys-pathconv \
  secret-pattern-detection hardcoded-path-check \
  cli-flag-verify skill-reference-verify stale-path-verify \
  workflow-resilience-check; do
  assert_absent "$g sources hook-utils without dirname" "$(cat "$HOOK_DIR/$g.sh")" \
    'source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"'
done

# --- no jq: several emitters yield ONE document, never a concatenation -------
# Build a PATH with no jq on it. A directory that carries jq is replaced by a
# shim directory re-exporting its other executables, so every other tool the
# dispatcher and the stubs need stays reachable.
NOJQ_PATH=""
IFS=: read -r -a path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
  [[ -n "$d" ]] || continue
  if [[ -x "$d/jq" || -x "$d/jq.exe" ]]; then
    shim="$TEST_TMPDIR/nojq-$(printf '%s' "$d" | tr -c 'A-Za-z0-9' _)"
    mkdir -p "$shim"
    for f in "$d"/*; do
      base="${f##*/}"
      [[ "$base" == jq || "$base" == jq.exe ]] && continue
      [[ -x "$f" ]] || continue
      ln -s "$f" "$shim/$base" 2>/dev/null || true
    done
    NOJQ_PATH+="${NOJQ_PATH:+:}$shim"
  else
    NOJQ_PATH+="${NOJQ_PATH:+:}$d"
  fi
done
if PATH="$NOJQ_PATH" type -P jq >/dev/null 2>&1; then
  bad "could not build a PATH without jq"
else
  run_nojq() { # run_nojq <stdin-string> <guard>... -> OUT, ERR, RC as run does
    local input="$1"
    shift
    : >"$SEEN"
    RC=0
    OUT=$(PATH="$NOJQ_PATH" "$BASH" "$DISPATCH" "$@" <<<"$input" 2>"$TEST_TMPDIR/err") || RC=$?
    ERR=$(cat "$TEST_TMPDIR/err")
  }
  run_nojq "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/ask.sh" "$TEST_TMPDIR/deny.sh" "$TEST_TMPDIR/ctx2.sh"
  assert_exit "no jq: run exits 0" 0 "$RC"
  assert_eq "no jq: exactly one JSON document on stdout" "1" "$(grep -c '^{' <<<"$OUT")"
  assert_eq "no jq: stdout is a single line" "1" "$(wc -l <<<"$OUT" | tr -d ' ')"
  assert_contains "no jq: the blocking document is the one emitted" "$OUT" '"permissionDecision":"deny"'
  assert_contains "no jq: dropped documents are named on stderr" "$ERR" "run-guards: dropped without jq:"
  assert_contains "no jq: the dropped context document is on stderr" "$ERR" "ctx one"
  assert_contains "no jq: the dropped ask document is on stderr" "$ERR" '"ask"'
  assert_absent "no jq: the emitted document is not also dropped" "$ERR" "stub deny"
  run_nojq "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/ask.sh"
  assert_contains "no jq: ask outranks a plain context document" "$OUT" '"ask"'
  run_nojq "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/ctx2.sh"
  assert_eq "no jq: with no blocking document the first one is emitted" "$standalone" "$OUT"
  assert_contains "no jq: the second context document is dropped to stderr" "$ERR" "ctx two"

  # The arbitration above runs on documents this file writes. With jq gone, two
  # SHIPPED guards each emit their own prerequisite notice on the same payload,
  # so the same code path can be asserted on documents the guards wrote — the
  # shape an operator without jq actually meets.
  NOJQ_CMD=$(command_json 'cat > foo.txt && git commit -m x')
  run_nojq "$NOJQ_CMD" block-hook-bypass.sh block-noncanonical-commit.sh
  assert_exit "no jq, real guards: the advisory notices exit 0" 0 "$RC"
  assert_eq "no jq, real guards: exactly one JSON document on stdout" \
    "1" "$(grep -c '^{' <<<"$OUT")"
  assert_contains "no jq, real guards: the first guard's notice is the one emitted" \
    "$OUT" "guardrails-block-hook-bypass: jq not found on PATH"
  assert_contains "no jq, real guards: the second guard's notice is dropped, prefixed" \
    "$ERR" "run-guards: dropped without jq:"
  assert_contains "no jq, real guards: the dropped notice names its guard" \
    "$ERR" "guardrails-block-noncanonical-commit: jq not found on PATH"
  assert_absent "no jq, real guards: the emitted notice is not also dropped" \
    "$ERR" "run-guards: dropped without jq: {\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"guardrails-block-hook-bypass"
  # A guard that denies on a missing prerequisite still denies through the
  # arbitration, and its reason still reaches stderr beside the dropped notice.
  run_nojq "$NOJQ_CMD" block-hook-bypass.sh block-no-verify.sh
  assert_exit "no jq, real guards: a fail-closed guard still wins the exit code" 2 "$RC"
  assert_contains "no jq, real guards: the fail-closed reason survives arbitration" \
    "$ERR" "the required prerequisite \`jq\` is not on PATH"
fi

# --- an unknown guard is reported, the rest still run ------------------------
run "$PAYLOAD" "$TEST_TMPDIR/nope.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "missing guard surfaces as rc 1" 1 "$RC"
assert_contains "missing guard is named" "$ERR" "guard not found"
assert_eq "the other guard still ran" $'git status --short\nBash' "$(cat "$SEEN")"

# --- in-process chain: a guard's exit ends the guard, never the dispatcher ---
# The guards are sourced into the dispatcher's own shell, so `exit` is a
# function there. These pin the shapes that function must get right: an exit
# from inside nested functions, an exit that runs in a real subshell (which
# must end that subshell only), a guard that falls off its end, `exit` with no
# argument, and a guard that dies of a hard error with its boundary installed,
# once and twice in one event.
stub nested.sh 'g() { echo nested >>"'"$SEEN"'"; exit 2; }
f() { g; echo NOTREACHED >>"'"$SEEN"'"; }
f
echo NOTREACHED2 >>"'"$SEEN"'"'
run "$PAYLOAD" "$TEST_TMPDIR/nested.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "exit from a nested function ends that guard with its status" 2 "$RC"
assert_eq "nothing after a nested exit runs, and the next guard still does" \
  $'nested\ngit status --short\nBash' "$(cat "$SEEN")"

stub subexit.sh 'v=$(exit 5); printf "sub=%s\n" "$?" >>"'"$SEEN"'"
( exit 6 ); printf "grp=%s\n" "$?" >>"'"$SEEN"'"
echo x | { read -r _; exit 7; }; printf "pipe=%s\n" "$?" >>"'"$SEEN"'"
exit 0'
run "$PAYLOAD" "$TEST_TMPDIR/subexit.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "exit inside a subshell ends the subshell only" 0 "$RC"
assert_eq "subshell exits keep their status and run the chain nowhere else" \
  $'sub=5\ngrp=6\npipe=7\ngit status --short\nBash' "$(cat "$SEEN")"

stub fall.sh 'echo fall >>"'"$SEEN"'"; false'
run "$PAYLOAD" "$TEST_TMPDIR/fall.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "a guard that falls off its end is recorded on its last status" 1 "$RC"
assert_eq "the guard after a fall-through still ran" $'fall\ngit status --short\nBash' "$(cat "$SEEN")"

stub noarg.sh 'false; exit'
run "$PAYLOAD" "$TEST_TMPDIR/noarg.sh"
assert_exit "exit with no argument carries the last command's status" 1 "$RC"

hard_stub() { # <name> <posture>: a guard with its boundary that dies of an unbound variable
  stub "$1" 'source "'"$HOOK_DIR"'/abort-boundary.sh"
guard::abort_boundary '"${1%.sh}"' PreToolUse '"$2"' 0 2
echo '"${1%.sh}"' >>"'"$SEEN"'"
: "${RUN_GUARDS_TEST_UNBOUND?forced abort}"
echo NOTREACHED >>"'"$SEEN"'"'
}
hard_stub hard.sh open
hard_stub hard2.sh open
hard_stub hardc.sh closed
run "$PAYLOAD" "$TEST_TMPDIR/hard.sh" "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/block.sh"
assert_exit "hard error: the guards after it still run and a block still wins" 2 "$RC"
assert_contains "hard error: the boundary names the guard on stderr" "$ERR" "guardrails hard: guard did not run"
assert_eq "hard error: the later guards ran once each" $'hard\ngit status --short\nBash' "$(cat "$SEEN")"
assert_contains "hard error: the notice document is emitted" "$(jq -r '.systemMessage' <<<"$OUT")" "guardrails hard:"
run "$PAYLOAD" "$TEST_TMPDIR/hard.sh" "$TEST_TMPDIR/hard2.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "two hard errors: the open posture exits 0" 0 "$RC"
assert_eq "two hard errors: exactly one JSON document on stdout" "1" "$(jq -s 'length' <<<"$OUT")"
two_hard=$(jq -r '.systemMessage' <<<"$OUT")
assert_contains "two hard errors: the first notice is in the merged document" "$two_hard" "guardrails hard:"
assert_contains "two hard errors: the second notice is in the merged document" "$two_hard" "guardrails hard2:"
assert_eq "two hard errors: every guard ran once" $'hard\nhard2\ngit status --short\nBash' "$(cat "$SEEN")"
run "$PAYLOAD" "$TEST_TMPDIR/hardc.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "hard error, closed posture: denies" 2 "$RC"
assert_contains "hard error, closed posture: the fail-closed line is on stderr" "$ERR" "fail-closed"
assert_silent "hard error, closed posture: no stdout document" "$OUT"
assert_eq "hard error, closed posture: the next guard still ran" $'hardc\ngit status --short\nBash' "$(cat "$SEEN")"

# Two real guards walk the same alias chain in one process. The alias memo in
# hook::git_alias_admit is per invocation: a memo hit means "already analyzed,
# skip". Left armed from block-dangerous-git's walk, it answered
# block-noncanonical-commit's walk of the same chain and that guard's
# --config-env refusal never fired. The dispatcher resets the analysis state
# before each guard, and this pins that both reasons reach stderr, as they did
# when each guard had its own process.
ALIAS_CMD='git -c "alias.sh=!git --config-env=alias.c=AV c --allow-empty -m x" sh'
alias_alone_rc=0
alias_alone_err=$(bash "$HOOK_DIR/block-noncanonical-commit.sh" <<<"$(command_json "$ALIAS_CMD")" 2>&1 >/dev/null) || alias_alone_rc=$?
assert_exit "alias chain: block-noncanonical-commit alone denies" 2 "$alias_alone_rc"
run "$(command_json "$ALIAS_CMD")" block-dangerous-git.sh block-noncanonical-commit.sh
assert_exit "alias chain: dispatched pair denies" 2 "$RC"
assert_contains "alias chain: the first guard's reason is on stderr" "$ERR" "block_dangerous_git_enabled"
assert_contains "alias chain: the second guard's reason is on stderr too (its memo was reset)" \
  "$ERR" "$(head -1 <<<"$alias_alone_err")"

# --- dual-blocked PowerShell sink: both denials print (#4236) ----------------
# Invoke-Command { git reset --hard } is unparsable (special-construct) and
# mutating. block-no-verify and block-dangerous-git both refuse it. Stopping
# the chain at the first exit 2 would hide the second lever; the dispatcher
# keeps walking so the operator sees both. Over-length (#4528) remains the
# one first-block short-circuit.
DUAL_PS=$(pwsh_command_json 'Invoke-Command -ScriptBlock { git reset --hard }')
run "$DUAL_PS" --lib lib/powershell/ps-command.sh block-no-verify.sh block-dangerous-git.sh
assert_exit "PS dual sink: dispatched pair denies" 2 "$RC"
assert_contains "PS dual sink: block-no-verify reason is on stderr" "$ERR" "block_no_verify_enabled"
assert_contains "PS dual sink: block-dangerous-git reason is on stderr too" "$ERR" "block_dangerous_git_enabled"

# --- a real guard decides the same inside the dispatcher as alone ------------
bypass=$(command_json 'git commit --no-verify -m x')
alone_rc=0
alone_err=$(bash "$HOOK_DIR/block-no-verify.sh" <<<"$bypass" 2>&1 >/dev/null) || alone_rc=$?
run "$bypass" --lib lib/powershell/ps-command.sh block-no-verify.sh block-dangerous-git.sh
assert_exit "real guard blocks through the dispatcher" 2 "$RC"
assert_eq "real guard: same exit alone and dispatched" "$alone_rc" "$RC"
assert_eq "real guard: same stderr alone and dispatched" "$alone_err" "$ERR"

# --- two REAL guards, one merged document ------------------------------------
# The merge above is asserted with stub guards, whose documents this file writes
# itself. The PostToolUse lane is where two SHIPPED guards emit on the same
# payload: a markdown file citing both a deleted path (stale-path-verify) and an
# unresolvable skill command (skill-reference-verify). Claude Code reads exactly
# one JSON document per hook process, so the two findings have to arrive merged
# into one additionalContext, in dispatch order — which is what these guards
# delivered as two separate hooks.
POST_REPO="$TEST_TMPDIR/post-lane"
mkdir -p "$POST_REPO/docs" "$POST_REPO/plugins/alpha/.claude-plugin" \
  "$POST_REPO/plugins/alpha/skills/setup"
git -C "$POST_REPO" init -q
jq -n '{name:"alpha",version:"0.1.0"}' >"$POST_REPO/plugins/alpha/.claude-plugin/plugin.json"
printf -- '---\nname: setup\ndescription: x\n---\n' >"$POST_REPO/plugins/alpha/skills/setup/SKILL.md"
printf 'x\n' >"$POST_REPO/docs/gone.md"
git -C "$POST_REPO" -c user.email=t@t.test -c user.name=t add -A >/dev/null 2>&1
git -C "$POST_REPO" -c user.email=t@t.test -c user.name=t commit -qm seed >/dev/null 2>&1
git -C "$POST_REPO" -c user.email=t@t.test -c user.name=t rm -q "docs/gone.md" >/dev/null 2>&1
git -C "$POST_REPO" -c user.email=t@t.test -c user.name=t commit -qm delete >/dev/null 2>&1
POST_TARGET="$POST_REPO/notes.md"
: >"$POST_TARGET"
POST_PAYLOAD=$(write_json "$POST_TARGET" \
  'See `docs/gone.md` and run `/alpha:nosuch` for details.')
POST_ENV=("CLAUDE_PROJECT_DIR=$POST_REPO" "CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30")

guard_invoke --via dispatched --payload "$POST_PAYLOAD" \
  --hook stale-path-verify.sh --also skill-reference-verify.sh -- "${POST_ENV[@]}"
assert_exit "two real emitters: advisory lane still exits 0" 0 "$GUARD_RC"
assert_eq "two real emitters: exactly one JSON document on stdout" \
  "1" "$(jq -s 'length' <<<"$GUARD_OUT")"
POST_CTX=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$GUARD_OUT")
POST_CTX="${POST_CTX//$'\r'/}" # the Windows jq build writes CRLF
assert_contains "two real emitters: the stale path is in the merged context" \
  "$POST_CTX" "STALE_PATH: docs/gone.md"
assert_contains "two real emitters: the unresolved skill is in the merged context" \
  "$POST_CTX" "UNRESOLVED_SKILL: /alpha:nosuch"
assert_eq "two real emitters: merged hookEventName kept" \
  "PostToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$GUARD_OUT")"
# Dispatch order decides the order of the merged blocks, as it decided the order
# of the two documents when these were separate hooks.
if [[ "${POST_CTX%%$'\n'*}" == stale-path-verify* ]]; then
  ok "two real emitters: merged in dispatch order"
else
  bad "two real emitters: merged out of dispatch order: ${POST_CTX%%$'\n'*}"
fi

# Each guard alone must say the same thing it said inside the merge.
for one in stale-path-verify skill-reference-verify; do
  guard_invoke --payload "$POST_PAYLOAD" --hook "$HOOK_DIR/$one.sh" -- "${POST_ENV[@]}"
  assert_eq "$one alone: one document" "1" "$(jq -s 'length' <<<"$GUARD_OUT")"
  assert_contains "merged context contains what $one says alone" "$POST_CTX" \
    "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$GUARD_OUT" | tr -d '\r' | head -2 | tail -1)"
done

# --- hooks.json wires every guard through the dispatcher by file name ---------
for g in secret-pattern-detection hardcoded-path-check block-no-verify block-dangerous-git \
  block-hook-bypass flag-commit-pr-skill-bypass block-noncanonical-commit \
  block-convention-violation block-windows-drive-tmp block-exported-msys-pathconv \
  block-root-delete-target cli-flag-verify skill-reference-verify stale-path-verify; do
  n=$(jq -r --arg g "$g.sh" '[.hooks[][] | .hooks[] | if (.args | type) == "array" then (.args | map(tostring) | join(" ")) else .command end | select(contains("run-guards.sh") and contains(" " + $g))] | length' "$HOOKS_JSON")
  if ((n > 0)); then ok "hooks.json dispatches $g"; else bad "hooks.json does not dispatch $g"; fi
  if [[ -f "$HOOK_DIR/$g.sh" ]]; then ok "$g.sh exists on disk"; else bad "$g.sh missing on disk"; fi
done

# --- PostToolUse rows carry an `if` per extension the verifiers accept --------
# Claude Code evaluates a handler's `if` before spawning it, so a Write to a file
# no verifier would scan spawns nothing. That saving holds only while the set of
# `if` extensions in hooks.json equals the set the three verifiers' own
# `case "$FILE"` gates accept: an extension added to a gate without an `if` row
# is a verifier that silently never fires on it, and an `if` row with no gate
# is a spawn that always early-exits. Both directions are pinned here, against
# the scripts' source rather than a second hand-kept list.
post_rows=$(jq -c '[.hooks.PostToolUse[] | select(.matcher == "Write|Edit") | .hooks[]]' "$HOOKS_JSON")
post_n=$(jq 'length' <<<"$post_rows")
if ((post_n > 1)); then ok "PostToolUse Write|Edit carries one row per gated extension ($post_n)"; else bad "PostToolUse Write|Edit carries $post_n row(s); expected one per gated extension"; fi
ungated=$(jq -r '[.[] | select(has("if") | not)] | length' <<<"$post_rows")
assert_eq "every PostToolUse Write|Edit row carries an if predicate" 0 "$ungated"
distinct_cmds=$(jq -r '[.[] | [.command, ((.args // []) | join(" ")), .timeout, .statusMessage]] | unique | length' <<<"$post_rows")
assert_eq "every PostToolUse row runs the same dispatcher line, timeout and statusMessage" 1 "$distinct_cmds"
gate_exts_of() { # $1 verifier name -> its case-gate extensions, one per line
  sed -n '/^case "\$FILE" in/,/^esac/p' "$HOOK_DIR/$1.sh" | grep -v '^[[:space:]]*#' | grep -oE '\*\.[a-z0-9]+' | sed 's/^\*\.//' | sort -u
}
if_exts=$(jq -r '.[] | .if | capture("^Edit\\(\\*\\.(?<e>[a-z0-9]+)\\)$") | .e' <<<"$post_rows" | sort -u | tr '\n' ' ')
gate_exts=$(for v in cli-flag-verify skill-reference-verify stale-path-verify; do gate_exts_of "$v"; done | sort -u | tr '\n' ' ')
assert_eq "if extensions equal the union of the verifiers' case gates" "$gate_exts" "$if_exts"
for v in cli-flag-verify skill-reference-verify stale-path-verify; do
  v_exts=$(gate_exts_of "$v" | tr '\n' ' ')
  for e in $v_exts; do
    if [[ " $if_exts " == *" $e "* ]]; then ok "$v gate *.$e has an if row"; else bad "$v gate *.$e has no if row"; fi
  done
done

# --- the dispatcher and the guards declare ONE contract ----------------------
# hooks/guard-requires.sh is where a guard states what it CONSUMES: the payload
# fields it reads, and the libraries it calls into. Two things are compiled
# from that declaration and nothing at run time re-derives either — the
# dispatcher's PRIME_FILTERS, and the `--lib` arguments in hooks.json — so this
# is where the three are held to each other, in both directions, against each
# guard's own source rather than against a second hand-kept list.
#
# Both directions cost something real. The cached hook::jq_fields is
# all-or-nothing per call, so a field a guard reads and the dispatcher does not
# prime spends a jq process on EVERY payload of that lane; a field primed that
# no guard reads is jq work nothing reads.
# shellcheck source=guard-requires.sh
source "$HOOK_DIR/guard-requires.sh"

prime_filters() { # the dispatcher's compiled union, read out of its own source
  awk -v q="'" '
    /^PRIME_FILTERS=\(/ { inarr = 1; next }
    inarr && /^\)/ { inarr = 0; next }
    inarr {
      line = $0
      while (match(line, q "[^" q "]*" q)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$1" | sort -u
}
guard_reads() { # <guard.sh> -> the literal filters its source hands jq_fields
  # The call plus its backslash continuations, single-quoted operands only: a
  # filter built from a variable (`.tool_input.files[$i].path`) names an index
  # the dispatcher cannot know and is never a candidate for priming.
  awk -v q="'" '
    /^[[:space:]]*#/ { next }
    index($0, "hook::jq_fields \"$INPUT\"") { incall = 1 }
    incall {
      cont = ($0 ~ /\\$/)
      line = $0
      while (match(line, q "[^" q "]*" q)) {
        tok = substr(line, RSTART + 1, RLENGTH - 2)
        if (substr(tok, 1, 1) == ".") print tok
        line = substr(line, RSTART + RLENGTH)
      }
      if (!cont) incall = 0
    }
  ' "$HOOK_DIR/$1" | sort -u
}
declared_fields() { # <guard.sh> -> its declared primed filters
  local -a f=()
  read -r -a f <<<"${GUARD_FIELDS[$1]-}"
  ((${#f[@]})) && printf '%s\n' "${f[@]}" | sort -u
  return 0
}
declared_unprimed() { # <guard.sh> -> its declared deliberately-unprimed filters
  local d="${GUARD_FIELDS_UNPRIMED[$1]-}"
  [[ -n "$d" ]] && printf '%s\n' "$d" | sort -u
  return 0
}
declared_libs() { # <guard.sh> -> the libraries it declared
  local -a l=()
  read -r -a l <<<"${GUARD_LIBS[$1]-}"
  ((${#l[@]})) && printf '%s\n' "${l[@]}" | sort -u
  return 0
}
guards_of() { # <hooks.json command> -> the guard file names it dispatches
  local -a toks=()
  read -r -a toks <<<"$1"
  local i=0 tok
  while ((i < ${#toks[@]})); do
    tok="${toks[i]}"
    if [[ "$tok" == "--lib" ]]; then
      ((i += 2))
      continue
    fi
    ((i++))
    [[ "$tok" == *.sh ]] || continue
    tok="${tok##*/}"
    [[ "$tok" == run-guards.sh ]] && continue
    printf '%s\n' "$tok"
  done
}
libs_of() { # <hooks.json command> -> its --lib operands
  local -a toks=()
  read -r -a toks <<<"$1"
  local i=0
  while ((i < ${#toks[@]})); do
    if [[ "${toks[i]}" == "--lib" ]] && ((i + 1 < ${#toks[@]})); then
      printf '%s\n' "${toks[i + 1]}"
      ((i += 2))
      continue
    fi
    ((i++))
  done
}
lines_of() { # <text> -> its non-empty lines, sorted, for comm
  printf '%s\n' "$1" | grep -v '^$' | sort -u
}

PRIMED=$(prime_filters "$DISPATCH")
PRIMED_N=$(lines_of "$PRIMED" | wc -l | tr -d ' ')
if ((PRIMED_N > 0)); then
  ok "PRIME_FILTERS reads back from run-guards.sh ($PRIMED_N filters)"
else
  bad "PRIME_FILTERS could not be read out of run-guards.sh"
fi
DISPATCH_CMDS=$(jq -r '.hooks[][] | .hooks[] | if (.args | type) == "array" then (.args | map(tostring) | join(" ")) else .command end | select(contains("run-guards.sh"))' "$HOOKS_JSON")
ALL_DISPATCHED=$(while IFS= read -r cmd; do guards_of "$cmd"; done <<<"$DISPATCH_CMDS" | sort -u)
DISPATCHED_N=$(lines_of "$ALL_DISPATCHED" | wc -l | tr -d ' ')
if ((DISPATCHED_N >= 10)); then
  ok "hooks.json dispatches $DISPATCHED_N guards through run-guards.sh"
else
  bad "hooks.json yielded only $DISPATCHED_N dispatched guards; the checks below would pass vacuously"
fi

while IFS= read -r g; do
  [[ -n "$g" ]] || continue
  decl=$(declared_fields "$g")
  if [[ -z "$decl" ]]; then
    bad "$g is dispatched but declares no fields in guard-requires.sh"
    continue
  fi
  known=$(printf '%s\n%s\n' "$decl" "$(declared_unprimed "$g")" | grep -v '^$' | sort -u)
  undeclared=$(comm -23 <(guard_reads "$g") <(printf '%s\n' "$known"))
  if [[ -z "$undeclared" ]]; then
    ok "$g reads only fields it declares"
  else
    bad "$g reads undeclared field(s), a jq spawn on every payload of its lane: $(tr '\n' ' ' <<<"$undeclared")"
  fi
  unread=$(comm -13 <(guard_reads "$g") <(lines_of "$decl"))
  if [[ -z "$unread" ]]; then
    ok "$g declares only fields it reads"
  else
    bad "$g declares field(s) its source never reads: $(tr '\n' ' ' <<<"$unread")"
  fi
  unprimed=$(comm -13 <(lines_of "$PRIMED") <(lines_of "$decl"))
  if [[ -z "$unprimed" ]]; then
    ok "$g's declared fields are all primed by the dispatcher"
  else
    bad "$g declares field(s) PRIME_FILTERS does not carry: $(tr '\n' ' ' <<<"$unprimed")"
  fi
  # A guard calls into the classifier exactly when it declares it. Declared and
  # unused is a ~104 KB parse for nothing; used and undeclared runs only
  # because a sibling guard on the same row happened to pull the library in.
  uses_ps=0
  grep -q 'ps::' "$HOOK_DIR/$g" && uses_ps=1
  has_lib=0
  [[ -n "$(declared_libs "$g")" ]] && has_lib=1
  if ((uses_ps == has_lib)); then
    ok "$g's library declaration matches its ps:: calls"
  elif ((uses_ps)); then
    bad "$g calls ps:: but declares no library in guard-requires.sh"
  else
    bad "$g declares a library it never calls into"
  fi
done <<<"$ALL_DISPATCHED"

# Nothing is primed that no dispatched guard — nor the dispatcher itself — asked
# for. run-guards.sh declares the two fields it reads under its own name.
WANTED=$(
  {
    declared_fields run-guards.sh
    while IFS= read -r g; do
      [[ -n "$g" ]] && declared_fields "$g"
    done <<<"$ALL_DISPATCHED"
  } | sort -u
)
orphan=$(comm -23 <(lines_of "$PRIMED") <(lines_of "$WANTED"))
if [[ -z "$orphan" ]]; then
  ok "every primed filter is declared by the dispatcher or by a guard it runs"
else
  bad "PRIME_FILTERS carries filter(s) no guard declares, primed on every payload for no reader: $(tr '\n' ' ' <<<"$orphan")"
fi

# Each dispatcher row's `--lib` set is the union of its guards' declarations. A
# guard whose library is missing from a row still loads it itself, so this is a
# budget statement rather than a correctness one: the load moves from once per
# event to once per guard.
while IFS= read -r cmd; do
  [[ -n "$cmd" ]] || continue
  row_libs=$(libs_of "$cmd" | sort -u)
  row_declared=$(while IFS= read -r g; do
    [[ -n "$g" ]] && declared_libs "$g"
  done < <(guards_of "$cmd") | sort -u)
  row_name=$(guards_of "$cmd" | head -1)
  if [[ "$row_libs" == "$row_declared" ]]; then
    ok "hooks.json row starting $row_name preloads exactly the libraries its guards declare"
  else
    bad "hooks.json row starting $row_name preloads [$(tr '\n' ' ' <<<"$row_libs")] against declarations [$(tr '\n' ' ' <<<"$row_declared")]"
  fi
done <<<"$DISPATCH_CMDS"

# --- a primed field is read by NAME, never by position -----------------------
# The dispatcher reads `.tool_name` to decide whether the event needs the
# PowerShell classifier. Read by index, a filter inserted ahead of it hands
# that decision a neighboring field's value: the classifier is then parsed on
# the Bash hot path and absent on the PowerShell one, with nothing at run time
# saying so. abort-boundary.test.sh pins the same property for the event name.
assert_absent "dispatcher reads no primed value by position" "$DISPATCH_SRC" 'RUN_GUARDS_VALUES['
SHIFT_DIR="$TEST_TMPDIR/prime-shift"
mkdir -p "$SHIFT_DIR/hooks" "$SHIFT_DIR/lib"
cp "$HOOK_DIR"/*.sh "$SHIFT_DIR/hooks/"
cp -R "$HOOK_DIR/../lib/powershell" "$SHIFT_DIR/lib/"
awk -v q="'" '{ print } /^PRIME_FILTERS=\(/ { print "  " q ".session_id" q }' \
  "$DISPATCH" >"$SHIFT_DIR/hooks/run-guards.sh"
assert_eq "the shifted copy primes one filter more than the shipped dispatcher" \
  "$((PRIMED_N + 1))" "$(prime_filters "$SHIFT_DIR/hooks/run-guards.sh" | wc -l | tr -d ' ')"
: >"$SEEN"
CLAUDE_PLUGIN_ROOT="$SHIFT_DIR" bash "$SHIFT_DIR/hooks/run-guards.sh" \
  --lib lib/powershell/ps-command.sh "$TEST_TMPDIR/lib.sh" <<<"$PAYLOAD" >/dev/null
assert_eq "a filter ahead of .tool_name: the Bash lane still skips the classifier" \
  "ps=unset" "$(cat "$SEEN")"
: >"$SEEN"
CLAUDE_PLUGIN_ROOT="$SHIFT_DIR" bash "$SHIFT_DIR/hooks/run-guards.sh" \
  --lib lib/powershell/ps-command.sh "$TEST_TMPDIR/lib.sh" <<<"$PWSH_PAYLOAD" >/dev/null
assert_eq "a filter ahead of .tool_name: the PowerShell lane still loads it" \
  "ps=1" "$(cat "$SEEN")"

# --- a guard reaches its declared library on BOTH paths ----------------------
# The dispatcher satisfies the declaration once for the event; alone, the guard
# satisfies the same declaration itself. Neither arm may leave `ps::` unbound,
# and a guard that declares no library must not gain one from a sibling.
expect_both "declared library reaches block-dangerous-git either way" 2 \
  --hook "$HOOK_DIR/block-dangerous-git.sh" --tool PowerShell \
  --command 'git push --force origin main' \
  --lib lib/powershell/ps-command.sh
expect_both "declared library reaches block-no-verify either way" 2 \
  --hook "$HOOK_DIR/block-no-verify.sh" --tool PowerShell \
  --command 'git commit --no-verify -m x' \
  --lib lib/powershell/ps-command.sh
# With no `--lib` on the row the dispatcher preloads nothing, and the guard's
# own declaration is what still binds `ps::`. One statement serves both paths,
# which is why a row that forgets the cue costs a repeated load and never a
# verdict.
guard_invoke --via dispatched --hook "$HOOK_DIR/block-dangerous-git.sh" \
  --tool PowerShell --command 'git push --force origin main'
assert_exit "a dispatched row with no --lib still reaches the declared library" 2 "$GUARD_RC"

# --- a project root that is not a repository does not scope the secret scan --
# The secret guard honors CLAUDE_PROJECT_DIR as a scope only when the root is a
# git work tree. Under the dispatcher, a non-repo root with a secret written
# outside it must still block. The token is assembled from parts so the joined
# literal never appears in this file.
SPD_NONREPO="$TEST_TMPDIR/spd-nonrepo"
mkdir -p "$SPD_NONREPO"
SPD_TOKEN="AKIA""IOSFODNN7EXAMPLE"
guard_invoke --via dispatched --hook "$HOOK_DIR/secret-pattern-detection.sh" \
  --payload "$(write_json "$TEST_TMPDIR/spd-elsewhere/config.env" "config = '$SPD_TOKEN'")" \
  -- "CLAUDE_PROJECT_DIR=$SPD_NONREPO"
assert_exit "dispatched secret guard: non-repo root, outside write blocks" 2 "$GUARD_RC"
assert_contains "dispatched secret guard: names the pattern" "$GUARD_ERR" "AWS Access Key"

# --- substitution count: refused before the first guard is sourced -----------
# The Bash row's cost grows with the number of command and process
# substitutions while every per-command cap still holds (#4684), and a row
# cancelled at its hooks.json timeout blocks nothing. Each run below is under
# `timeout 20`, a hang backstop and the only timing check: a wall-clock
# threshold on a shared shard would measure the shard.
BASH_ROW=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[0] | if (.args | type) == "array" then (.args | map(tostring) | join(" ")) else .command end' "$HOOKS_JSON")
read -r -a BASH_ROW_ARGS <<<"${BASH_ROW#*run-guards.sh }"
ROW_CAP=""
for ((i = 0; i + 1 < ${#BASH_ROW_ARGS[@]}; i++)); do
  [[ "${BASH_ROW_ARGS[i]}" == --max-substitutions ]] && ROW_CAP=${BASH_ROW_ARGS[i + 1]}
done
if [[ "$ROW_CAP" =~ ^[1-9][0-9]*$ ]]; then
  ok "the Bash row passes --max-substitutions $ROW_CAP"
else
  bad "the Bash row passes no --max-substitutions cap"
  ROW_CAP=256
fi

subst_cmd() { # <n> [tail]: `echo ` then <n> sibling `$(: rm)`, then <tail>
  local s="echo " k
  for ((k = 0; k < $1; k++)); do s+='$(: rm)'; done
  printf '%s%s' "$s" "${2-}"
}
rep() { # <text> <n>
  local s="" k
  for ((k = 0; k < $2; k++)); do s+="$1"; done
  printf '%s' "$s"
}
tool_payload() { # <tool> <command>
  jq -n --arg t "$1" --arg c "$2" '{tool_name:$t,cwd:"/x",tool_input:{command:$c}}'
}
cap_run() { # <stdin> <run-guards argv>... -> OUT, ERR, RC
  local input="$1"
  shift
  : >"$SEEN"
  RC=0
  OUT=$(timeout 20 bash "$DISPATCH" "$@" <<<"$input" 2>"$TEST_TMPDIR/err") || RC=$?
  ERR=$(cat "$TEST_TMPDIR/err")
}
CAP_MSG="more than the $ROW_CAP the guards can read"

cap_run "$(tool_payload Bash "$(subst_cmd "$ROW_CAP")")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: a command at the cap reaches the guards" 0 "$RC"
assert_contains "cap: the guard ran on a command at the cap" "$(cat "$SEEN")" 'echo $(: rm)'
cap_run "$(tool_payload Bash "$(subst_cmd "$((ROW_CAP + 1))")")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: one past the cap is refused" 2 "$RC"
assert_contains "cap: the refusal names the cap" "$ERR" "$CAP_MSG"
assert_contains "cap: the refusal names the count" "$ERR" "holds $((ROW_CAP + 1)) command or process substitutions"
assert_eq "cap: no guard is sourced past the cap" "" "$(cat "$SEEN")"
cap_run "$(tool_payload Bash "$(subst_cmd 2339)")" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: without --max-substitutions nothing is counted" 0 "$RC"

# A single-quoted span does not count. Every reading bash, the library or the
# root-delete guard's substitution scan could take differently counts, and so
# does a command naming anything a guard re-parses an argument of. A refusal
# must come from the count: rc=70 or an unbound variable would be the
# dispatcher failing, which allows the command.
OVER=$((ROW_CAP + 1))
QS=$(rep '$(:)' "$OVER")
NL=$'\n'
TAB=$'\t'
cap_quoted() { # <label> <expected rc> <command>
  cap_run "$(tool_payload Bash "$3")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
  assert_exit "cap quoted: $1" "$2" "$RC"
  assert_absent "cap quoted: $1, no could-not-run" "$ERR" "rc=70"
  assert_absent "cap quoted: $1, no unbound variable" "$ERR" "unbound variable"
  if [[ $2 == 2 ]]; then
    assert_contains "cap quoted: $1, refused by the count" "$ERR" "$CAP_MSG"
  else
    assert_contains "cap quoted: $1, the guard ran" "$(cat "$SEEN")" "Bash"
  fi
}
# Every spelling: skipped in single quotes, counted unquoted and in double
# quotes. Backticks count in pairs.
for spelling in '<(:)' '>(:)' '$((1))' '$(:)' '"$(:)"' '`:`'; do
  many=$(rep "$spelling" "$OVER")
  cap_quoted "$OVER of $spelling in one single-quoted string reach the guards" 0 "echo '$many'"
  cap_quoted "$OVER of $spelling unquoted are refused" 2 "echo $many"
  cap_quoted "$OVER of $spelling in double quotes are refused" 2 "echo \"${many//\"/}\""
done
cap_quoted "$OVER in one single-quoted span reach the guards" 0 "echo '$QS'"
cap_quoted "$OVER single-quoted spans reach the guards" 0 "echo $(rep "'\$(:)'" "$OVER")"
cap_quoted "$OVER backtick pairs in a quoted body reach the guards" 0 "gh pr create --title 'x' --body '$(rep '`a` in Git Bash ' "$OVER")'"
cap_quoted "a PR-body-like command with 300 inline-code spans reaches the guards" 0 "gh pr create --title 'x' --body '$(rep 'Run `check` first. ' 300)'"
cap_quoted "quoted spans over the cap and unquoted ones under it reach the guards" 0 "echo '$(rep '$(:)' 300)' $(rep '$(:)' 100)"
cap_quoted "unquoted spans over the cap count beside quoted ones under it" 2 "echo '$(rep '$(:)' 100)' $QS"
cap_quoted "a plain comment before the span is skipped" 0 "# note${NL}echo '$QS'"
cap_quoted "a mid-word # starts no comment" 0 "x#'${NL}$QS${NL}'"
cap_quoted "an unclosed single quote counts" 2 "echo '$QS"
cap_quoted "a single quote inside double quotes is literal" 2 "echo \"it's\" $QS '"
cap_quoted "an escaped \\' opens no span" 2 "echo \\' $QS \\'"
cap_quoted "an ANSI-C span counts" 2 "echo \$'$QS'"
cap_quoted "\$\$' counts" 2 "echo \$\$'$QS'"
cap_quoted "a span after \\\$ counts" 2 "echo \\\$'$QS'"
cap_quoted "a quote in a comment counts the rest" 2 "# it's${NL}echo '$QS'"
cap_quoted "a backtick outside a span counts the rest" 2 "echo \`:\` '$QS'"
cap_quoted "a substitution in double quotes counts the rest" 2 "echo \"\$(:)\" '$QS'"
# A quoted-delimiter heredoc body does not count; bash expands an unquoted one.
for form in "'EOF'" '"EOF"' '\EOF' "E'O'F"; do
  cap_quoted "a <<$form body reaches the guards" 0 "cat <<$form${NL}$QS${NL}EOF"
  cap_quoted "$OVER backtick pairs in a <<$form body reach the guards" 0 "cat <<$form${NL}$(rep '`:`' "$OVER")${NL}EOF"
done
cap_quoted "a <<-'EOF' body ends at a tab-indented terminator" 0 "cat <<-'EOF'${NL}$QS${NL}${TAB}EOF"
cap_quoted "a <<'EOF' body does not end at a tab-indented line" 2 "cat <<'EOF'${NL}$QS${NL}${TAB}EOF"
cap_quoted "a PR body through --body-file - reaches the guards" 0 "gh pr create --title 'x' --body-file - <<'EOF'${NL}$(rep 'Run `check` first. ' 300)${NL}EOF"
cap_quoted "a body ends at its own terminator, not a longer line" 0 "cat <<'EOF'${NL}EOFX${NL}$QS${NL}EOF"
XS=$(rep '$(: x) ' "$OVER")
cap_quoted "$OVER \$(: x) in a <<'EOF' body reach the guards" 0 "cat <<'EOF'${NL}$XS${NL}EOF"
cap_quoted "$OVER \$(: x) in an unquoted <<EOF body count" 2 "cat <<EOF${NL}$XS${NL}EOF"
cap_quoted "$OVER \$(: x) after a <<'EOF' body count" 2 "cat <<'EOF'${NL}x${NL}EOF${NL}echo $XS"
cap_quoted "an unquoted <<EOF body counts" 2 "cat <<EOF${NL}$QS${NL}EOF"
cap_quoted "an expanding heredoc counts" 2 "cat <<EOF${NL}\$(rm -rf /) $QS${NL}EOF"
cap_quoted "an empty delimiter counts" 2 "cat <<''${NL}$QS${NL}"
cap_quoted "a quoted heredoc body with no terminator counts" 2 "cat <<'EOF'${NL}$QS"
cap_quoted "text after the terminator counts" 2 "cat <<'EOF'${NL}x${NL}EOF${NL}echo $QS"
cap_quoted "a single-quoted span after a body counts" 2 "cat <<'EOF'${NL}don't${NL}EOF${NL}echo '$QS'"
cap_quoted "a second heredoc on the line counts" 2 "cat <<'A' <<'EOF'${NL}x${NL}A${NL}$QS${NL}EOF"
cap_quoted "a quote after the delimiter counts" 2 "cat <<'EOF' # it's${NL}$QS${NL}EOF"
cap_quoted "a heredoc inside \"\$(...)\" counts" 2 "git commit -m \"\$(cat <<'EOF'${NL}$QS${NL}EOF${NL})\""
cap_quoted "a heredoc inside \$(...) counts" 2 "x=\$(cat <<'EOF'${NL}$QS${NL}EOF${NL})"
cap_quoted "a heredoc fed to a shell counts" 2 "bash <<'EOF'${NL}$QS${NL}EOF"
cap_quoted "a heredoc piped to a shell counts" 2 "cat <<'EOF' | sh${NL}$QS${NL}EOF"
cap_quoted "a heredoc sourced from stdin counts" 2 "source /dev/stdin <<'EOF'${NL}$QS${NL}EOF"
cap_quoted "a heredoc dotted from stdin counts" 2 ". /dev/stdin <<'EOF'${NL}$QS${NL}EOF"
cap_quoted "a heredoc dotted after a separator counts" 2 "cd x; . /dev/stdin <<'EOF'${NL}$QS${NL}EOF"
cap_quoted "a heredoc dotted from a tab-separated file counts" 2 ".${TAB}/dev/stdin <<'EOF'${NL}$QS${NL}EOF"
cap_quoted "a heredoc dotted through \$IFS counts" 2 ".\$IFS/dev/stdin <<'EOF'${NL}$QS${NL}EOF"
cap_quoted "a heredoc dotted through \${IFS} counts" 2 ".\${IFS}/dev/stdin <<'EOF'${NL}$QS${NL}EOF"
cap_quoted "a dot inside a word does not count a quoted body" 0 "cat ./a.txt <<'EOF'${NL}$QS${NL}EOF"
cap_quoted "a span in (( )) counts" 2 "(( '$QS' ))"
cap_quoted "a span in \${x:offset} counts" 2 "echo \${x:'$QS'}"
cap_quoted "a span in an array subscript counts" 2 "a['$QS']=5"
for cmd in "eval '$QS'" "bash -c '$QS'" "sudo sh -lc '$QS'" "'/bin/bash' -c '$QS'" "b'ash' -c '$QS'" \
  "git -c 'alias.x=!$QS' x"; do
  cap_quoted "a re-parsed argument counts: ${cmd:0:24}" 2 "$cmd"
done
cap_quoted "a re-parsed argument counts: a Windows-path shell" 2 "\"C:\\Program Files\\Git\\bin\\bash.exe\" -c '$QS'" # portability-ok: a Windows path in the command under test, not a GNU grep word boundary
# 16 KB of the shape that costs the scan the most steps finishes well inside
# the timeout backstop.
cap_quoted "a 16 KB command of tiny spans is refused" 2 "echo $(rep "'a'\$(:)" 2300)"
cap_run "$(tool_payload Bash "echo $(rep '`:`' "$ROW_CAP")")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: $ROW_CAP backtick pairs reach the guards" 0 "$RC"
cap_run "$(tool_payload Bash "echo $(rep '`:`' "$ROW_CAP")\`")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: an unpaired backtick past the pairs counts as one more" 2 "$RC"
cap_run "$(tool_payload PowerShell "echo $(rep '$(1)' "$((ROW_CAP + 1))")")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: a PowerShell command past the cap is refused" 2 "$RC"
cap_run "$(tool_payload PowerShell "echo '$(rep '$(1)' "$((ROW_CAP + 1))")'")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: a PowerShell command counts single-quoted text" 2 "$RC"
cap_run "$(write_json "$TEST_TMPDIR/w.txt" "$(rep '$(:)' "$((ROW_CAP + 1))")")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: a payload with no command field is not counted" 0 "$RC"
# An unprimed payload (a NUL in it) is counted whole.
cap_nul=$(jq -n --arg c "$(subst_cmd "$((ROW_CAP + 1))")" '{tool_name:"Bash",tool_input:{command:($c + ([0] | implode))}}')
cap_run "$cap_nul" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/nul.sh"
assert_exit "cap: an unprimed payload past the cap is refused" 2 "$RC"
cap_nul=$(jq -n '{tool_name:"Bash",tool_input:{command:("git " + ([0] | implode) + "x")}}')
cap_run "$cap_nul" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/nul.sh"
assert_eq "cap: an unprimed payload under the cap reaches the guard" "nul=1 cmd=git x" "$(cat "$SEEN")"
cap_run "$PAYLOAD" --max-substitutions 0 "$TEST_TMPDIR/block.sh"
assert_exit "cap: a malformed cap is the dispatcher's could-not-run, not a verdict" 0 "$RC"
assert_contains "cap: the malformed cap is reported" "$ERR" "rc=70"

# The shipped row, with every guard on it. At the cap the guards judge the
# command, so a root delete behind the substitutions is refused by its own
# guard; past it, the two measured payloads (#4684) are refused by the count.
cap_run "$(tool_payload Bash "$(subst_cmd "$ROW_CAP")")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: a benign command at the cap is allowed" 0 "$RC"
cap_run "$(tool_payload Bash "$(subst_cmd "$ROW_CAP" '; rm -rf /')")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: a root delete at the cap is refused" 2 "$RC"
assert_contains "cap row: the root-delete guard refused it" "$ERR" "filesystem root"
assert_absent "cap row: the count did not" "$ERR" "$CAP_MSG"
cap_run "$(tool_payload Bash "$(subst_cmd 2339)")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: 2,339 sibling substitutions are refused" 2 "$RC"
assert_contains "cap row: 2,339 are refused by the count" "$ERR" "$CAP_MSG"
cap_run "$(tool_payload Bash "$(subst_cmd 2330 '; rm -rf /')")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: 2,330 substitutions then a root delete are refused" 2 "$RC"
assert_contains "cap row: that one is refused by the count too" "$ERR" "$CAP_MSG"
# Single-quoted, the same payload reaches the guards, and a root delete behind
# it is refused by its own guard, not by the count.
cap_run "$(tool_payload Bash "echo '$(rep '$(: rm)' 2339)'")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: 2,339 single-quoted substitutions reach the guards" 0 "$RC"
cap_run "$(tool_payload Bash "echo '$(rep '$(: rm)' 2300)'; rm -rf /")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: a root delete after them is refused" 2 "$RC"
assert_contains "cap row: the root-delete guard refused it" "$ERR" "filesystem root"
assert_absent "cap row: the count did not" "$ERR" "$CAP_MSG"
# A quoted heredoc body reaches the guards, and the root-delete guard still
# reads the substitutions in it. Fed to a shell, the body counts.
cap_run "$(tool_payload Bash "cat <<'EOF'${NL}$(rep '$(: rm) ' 2000)${NL}EOF")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: 2,000 substitutions in a quoted heredoc body reach the guards" 0 "$RC"
cap_run "$(tool_payload Bash "bash <<'EOF'${NL}\$(rm -rf /)${NL}EOF")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: bash <<'EOF' with a root delete in a substitution is refused" 2 "$RC"
assert_contains "cap row: the root-delete guard refused it" "$ERR" "filesystem root"
cap_run "$(tool_payload Bash "bash <<'EOF'${NL}$(rep '$(: rm) ' 300)rm -rf /${NL}EOF")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: bash <<'EOF' with 300 substitutions then a root delete is refused" 2 "$RC"
assert_contains "cap row: that one is refused by the count" "$ERR" "$CAP_MSG"
# --- over-length: the first block ends the chain (#4528) ----------------------
# Past --max-command-len the guards after a block would only add reasons to a
# decided verdict, and a row that outlives its hooks.json timeout is cancelled
# with the block discarded. Below or at the ceiling every guard still runs.
BIG_CMD=$(printf '%*s' 20000 '' | tr ' ' x)
BIG_PAYLOAD=$(jq -nc --arg c "$BIG_CMD" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:$c}}')
AT_CMD=$(printf '%*s' 16384 '' | tr ' ' x)
AT_PAYLOAD=$(jq -nc --arg c "$AT_CMD" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:$c}}')
over_run() { # <payload> <dispatcher arg>... -> OUT ERR RC, SEEN reset
  local payload="$1"
  shift
  : >"$SEEN"
  OUT=$(bash "$DISPATCH" "$@" <<<"$payload" 2>"$TEST_TMPDIR/over.err")
  RC=$?
  ERR=$(cat "$TEST_TMPDIR/over.err")
}
over_run "$BIG_PAYLOAD" --max-command-len 16384 "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "over the ceiling: the block stands" 2 "$RC"
assert_contains "over the ceiling: the block reason reaches stderr" "$ERR" "BLOCKED: stub"
assert_eq "over the ceiling: no guard runs after the block" "0" "$(grep -c . "$SEEN")"
over_run "$BIG_PAYLOAD" --max-command-len 16384 "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "over the ceiling: a guard ahead of the block still runs" 2 "$RC"
assert_eq "over the ceiling: only the guard ahead of the block ran" "1" "$(grep -c '^x' "$SEEN")"
over_run "$AT_PAYLOAD" --max-command-len 16384 "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "at the ceiling: the block wins" 2 "$RC"
assert_eq "at the ceiling: the guard after the block still runs" "1" "$(grep -c '^x' "$SEEN")"
over_run "$BIG_PAYLOAD" "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/allow.sh"
assert_eq "no --max-command-len: the guard after the block still runs" "1" "$(grep -c '^x' "$SEEN")"
# A NUL leaves the payload unprimed; its own length stands in for the
# command's, which it can only exceed.
NUL_BIG_PAYLOAD=$(jq -nc --arg c "$BIG_CMD" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:($c + "\u0000")}}')
over_run "$NUL_BIG_PAYLOAD" --max-command-len 16384 "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/nul.sh"
assert_exit "unprimed over the ceiling: the block stands" 2 "$RC"
assert_eq "unprimed over the ceiling: no guard runs after the block" "0" "$(grep -c . "$SEEN")"
over_run "$PAYLOAD" --max-command-len 16k "$TEST_TMPDIR/allow.sh"
assert_eq "a --max-command-len that is not a whole number runs no guard" "" "$(cat "$SEEN")"
assert_contains "a --max-command-len that is not a whole number is reported" "$OUT$ERR" "run-guards"

# The shipped row. The guards carrying a MAX_COMMAND_LEN ceiling refuse an
# over-length command before they tokenize it, so the row answers at once and
# the uncapped guards never see it. Each ceiling guard keeps its kill switch:
# with the first disabled, the next one blocks.
BASH_ROW=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[] | if (.args | type) == "array" then (.args | map(tostring) | join(" ")) else .command end' "$HOOKS_JSON")
read -r -a BASH_ROW_TOKS <<<"$BASH_ROW"
BASH_ROW_ARGS=()
for ((i = 0; i < ${#BASH_ROW_TOKS[@]}; i++)); do
  [[ "${BASH_ROW_TOKS[i]}" == */run-guards.sh ]] || continue
  BASH_ROW_ARGS=("${BASH_ROW_TOKS[@]:i+1}")
  break
done
ROW_MAX=""
for ((i = 0; i + 1 < ${#BASH_ROW_ARGS[@]}; i++)); do
  [[ "${BASH_ROW_ARGS[i]}" == --max-command-len ]] && ROW_MAX=${BASH_ROW_ARGS[i + 1]}
done
assert_eq "the Bash|PowerShell row declares --max-command-len" "16384" "$ROW_MAX"
ceiling_guards=0
for g in $(guards_of "$BASH_ROW"); do
  g_max=$(sed -n 's/^MAX_COMMAND_LEN=\([0-9]*\)$/\1/p' "$HOOK_DIR/$g")
  [[ -n "$g_max" ]] || continue
  ceiling_guards=$((ceiling_guards + 1))
  assert_eq "$g's MAX_COMMAND_LEN equals the row's --max-command-len" "$ROW_MAX" "$g_max"
done
if ((ceiling_guards >= 2)); then
  ok "the Bash|PowerShell row runs $ceiling_guards guards that carry the ceiling"
else
  bad "the Bash|PowerShell row runs $ceiling_guards guards that carry the ceiling; the short-circuit needs one to block"
fi
first_guard=$(guards_of "$BASH_ROW" | head -1)
if [[ -n "$(sed -n 's/^MAX_COMMAND_LEN=\([0-9]*\)$/\1/p' "$HOOK_DIR/$first_guard")" ]]; then
  ok "the row's first guard ($first_guard) carries the ceiling, so an over-length command is refused before any tokenize"
else
  bad "the row's first guard ($first_guard) carries no ceiling: an over-length command is tokenized before any guard refuses it"
fi

HEREDOC_BODY=""
while ((${#HEREDOC_BODY} < 70000)); do HEREDOC_BODY+=$'The quick brown fox jumps over the lazy dog, again.\n'; done
# Through stdin, not `--arg`: a native jq.exe gets the command line whole, and
# Windows caps one at 32,767 characters, so a 70 KB argument leaves the payload
# empty and every row case below sees no command at all.
HEREDOC_PAYLOAD=$(printf '%s' "cat > /tmp/out.txt <<'EOF'"$'\n'"${HEREDOC_BODY}EOF" |
  jq -Rsc '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:.}}')
[[ ${#HEREDOC_PAYLOAD} -gt 70000 ]] || bad "the ~70 KB payload was not built (${#HEREDOC_PAYLOAD} chars)"
row_t0=${EPOCHREALTIME:-}
ROW_ERR=$(cd "$HOOK_DIR" && RUN_GUARDS_PROFILE=1 bash "$DISPATCH" "${BASH_ROW_ARGS[@]}" <<<"$HEREDOC_PAYLOAD" 2>&1 >/dev/null)
ROW_RC=$?
row_t1=${EPOCHREALTIME:-}
assert_exit "the shipped row blocks a ~70 KB command" 2 "$ROW_RC"
assert_contains "the shipped row names the ceiling" "$ROW_ERR" "too long to parse safely"
assert_eq "the shipped row runs one guard on a ~70 KB command" "1" "$(grep -c '^run-guards: .* ms rc=' <<<"$ROW_ERR")"
if [[ -n "$row_t0" && -n "$row_t1" ]]; then
  row_ms=$(((${row_t1/./} - ${row_t0/./}) / 1000))
  # A tenth of the row's 60-second timeout; measured at 64 ms.
  if ((row_ms < 6000)); then
    ok "the shipped row answers a ~70 KB command in ${row_ms} ms"
  else
    bad "the shipped row took ${row_ms} ms on a ~70 KB command"
  fi
fi
ROW_ERR=$(cd "$HOOK_DIR" && CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED=false RUN_GUARDS_PROFILE=1 \
  bash "$DISPATCH" "${BASH_ROW_ARGS[@]}" <<<"$HEREDOC_PAYLOAD" 2>&1 >/dev/null)
ROW_RC=$?
assert_exit "first ceiling guard disabled: the row still blocks" 2 "$ROW_RC"
assert_contains "first ceiling guard disabled: the next ceiling guard is the one that blocks" \
  "$(grep '^run-guards: .* ms rc=2' <<<"$ROW_ERR")" "block-dangerous-git.sh"

# --- one tokenization per event -----------------------------------------------
# Every guard that parses the event's command gets the segments a parse of its
# own would report, argv and HOOK_SEG_* alike, while the string is walked once.
# A parse cut short by a guard's `exit` inside its callback is never kept.
# count.sh wraps the library's uncached parse to tally the strings it walks;
# the wrapper is defined in the dispatcher's shell, so the tally covers every
# guard after it.
stub count.sh '[[ -n "$(declare -F bps_orig_uncached)" ]] || {
  eval "bps_orig_uncached() $(declare -f hook::bash_parse_segments_uncached | tail -n +2)"
  hook::bash_parse_segments_uncached() {
    printf "walk %q\n" "$1" >>"'"$SEEN"'.walks"
    bps_orig_uncached "$@"
  }
}
exit 0'
PARSE_BODY='bps_cb() {
  local rec="$PARSE_LABEL:" j
  rec+=" [$*] q=[${HOOK_SEG_WORD_QUOTED[*]-}]"
  for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
    rec+=" R:${HOOK_SEG_REDIR_OP[j]}|${HOOK_SEG_REDIR_FD[j]}|${HOOK_SEG_REDIR_TARGET[j]}|${HOOK_SEG_REDIR_QUOTED[j]}|${HOOK_SEG_REDIR_OPAQUE[j]}"
  done
  printf "%s\n" "$rec" >>"'"$SEEN"'"
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" bps_cb
  fi
  [[ -n "${PARSE_EXIT_ON:-}" && "$1" == "$PARSE_EXIT_ON" ]] && exit 2
  return 0
}
hook::buffer_stdin_to INPUT || exit 0
hook::jq_fields "$INPUT" ".tool_input.command" || exit 0
hook::bash_parse_segments "${HOOK_JQ_FIELDS[0]}" bps_cb
exit 0'
stub parse-a.sh "PARSE_LABEL=a; PARSE_EXIT_ON=; ${PARSE_BODY}"
stub parse-b.sh "PARSE_LABEL=b; PARSE_EXIT_ON=; ${PARSE_BODY}"
stub parse-c.sh "PARSE_LABEL=c; PARSE_EXIT_ON=; ${PARSE_BODY}"
stub parse-exit.sh "PARSE_LABEL=x; PARSE_EXIT_ON=echo; ${PARSE_BODY}"
SHARE_CMD=$'git commit -m "héllo ✓" 2>&1 >out.log && bash -c \'echo inner > f\'; cat <<EOF >>log\nbody\nEOF\necho "tail" <in'
SHARE_PAYLOAD=$(jq -nc --arg c "$SHARE_CMD" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:$c}}')
printf -v SHARE_WALK 'walk %q' "$SHARE_CMD"
share_by_label() { # <label> -> that guard's records, label stripped
  sed -n "s/^$1://p" "$SEEN"
}
: >"$SEEN"
bash "$TEST_TMPDIR/parse-a.sh" <<<"$SHARE_PAYLOAD" >/dev/null 2>&1
SHARE_ALONE=$(share_by_label a)
: >"$SEEN"
: >"$SEEN.walks"
bash "$DISPATCH" "$TEST_TMPDIR/count.sh" "$TEST_TMPDIR/parse-a.sh" "$TEST_TMPDIR/parse-b.sh" \
  "$TEST_TMPDIR/parse-c.sh" <<<"$SHARE_PAYLOAD" >/dev/null 2>&1
assert_eq "shared parse: the first guard sees what it sees alone" "$SHARE_ALONE" "$(share_by_label a)"
assert_eq "shared parse: a replaying guard sees the same segments" "$SHARE_ALONE" "$(share_by_label b)"
assert_eq "shared parse: a third guard sees the same segments" "$SHARE_ALONE" "$(share_by_label c)"
assert_contains "shared parse: the redirections ride along" "$SHARE_ALONE" "R:>&|2|1|0|0 R:>||out.log|0|0"
assert_eq "shared parse: the event's command is walked once" "1" \
  "$(grep -cxF "$SHARE_WALK" "$SEEN.walks")"
assert_eq "shared parse: a callback's re-parse is walked per guard, never cached" "3" \
  "$(grep -cxF 'walk echo\ inner\ \>\ f' "$SEEN.walks")" # portability-ok: grep -F fixed string of a recorded walk token, not a GNU word boundary
: >"$SEEN"
: >"$SEEN.walks"
bash "$DISPATCH" "$TEST_TMPDIR/count.sh" "$TEST_TMPDIR/parse-exit.sh" "$TEST_TMPDIR/parse-b.sh" \
  "$TEST_TMPDIR/parse-c.sh" <<<"$SHARE_PAYLOAD" >/dev/null 2>&1
SHARE_RC=$?
assert_exit "shared parse: a guard that exits mid-parse still blocks" 2 "$SHARE_RC"
assert_eq "shared parse: after a cut-short parse the next guard sees every segment" "$SHARE_ALONE" "$(share_by_label b)"
assert_eq "shared parse: and the guard after it too" "$SHARE_ALONE" "$(share_by_label c)"
assert_eq "shared parse: a cut-short parse is not kept, so the command is walked twice" "2" \
  "$(grep -cxF "$SHARE_WALK" "$SEEN.walks")"

report
