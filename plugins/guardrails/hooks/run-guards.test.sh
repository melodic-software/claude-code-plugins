#!/usr/bin/env bash
# Contract tests for hooks/run-guards.sh, the one-process dispatcher that runs
# several guards for one hook event. The guards' own decisions are covered by
# their own *.test.sh; this file covers what the dispatcher owns: stdin read
# once and re-served with the same rc, jq answered from one cache with a
# byte-identical fallback, every guard run to completion, exit aggregation,
# and the merge of several stdout documents into one.
#
# The stub guard bodies below are single-quoted on purpose: they are written
# verbatim into stub scripts, so their `$` must not expand here.
# shellcheck disable=SC2016
set -uo pipefail

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/run-guards-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="$HOOK_DIR/run-guards.sh"
# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$HOOK_DIR/.."
export CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for these tests" >&2
  exit 1
fi

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
stub allow.sh 'INPUT=$(hook::buffer_stdin) || { rc=$?; ((rc == 2)) && exit 2; exit 0; }
hook::jq_fields "$INPUT" ".tool_input.command" ".tool_name" || exit 0
printf "%s\n" "${HOOK_JQ_FIELDS[@]}" >>"'"$SEEN"'"
exit 0'
stub block.sh 'echo "BLOCKED: stub" >&2; exit 2'
stub ctx1.sh 'hook::emit_channels PreToolUse "ctx one" ""; exit 0'
stub ctx2.sh 'hook::emit_channels PreToolUse "ctx two" "sys two"; exit 0'
stub crash.sh 'exit 3'
stub nul.sh 'INPUT=$(hook::buffer_stdin) || exit 0
hook::jq_fields "$INPUT" ".tool_input.command" || exit 0
printf "nul=%s cmd=%s\n" "$HOOK_JQ_FIELDS_NUL" "$HOOK_JQ_FIELDS" >>"'"$SEEN"'"'
stub miss.sh 'INPUT=$(hook::buffer_stdin) || exit 0
hook::jq_fields "$INPUT" ".session_id" ".tool_name" || exit 0
printf "%s\n" "${HOOK_JQ_FIELDS[@]}" >>"'"$SEEN"'"'
stub lib.sh 'printf "ps=%s\n" "${_GUARDRAILS_PS_COMMAND_LOADED:-unset}" >>"'"$SEEN"'"'

PAYLOAD=$(jq -n '{session_id:"s-1",tool_name:"Bash",cwd:"/x",tool_input:{command:"git status --short"}}')

run() { # run <stdin-string> <guard>... -> stdout captured, stderr to $ERR, rc in $RC
  local input="$1"
  shift
  : >"$SEEN"
  RC=0
  OUT=$(bash "$DISPATCH" "$@" <<<"$input" 2>"$TEST_TMPDIR/err") || RC=$?
  ERR=$(cat "$TEST_TMPDIR/err")
}

# --- benign payload, one allowing guard ---------------------------------------
run "$PAYLOAD" "$TEST_TMPDIR/allow.sh"
assert_exit "allow-only exits 0" 0 "$RC"
assert_silent "allow-only prints nothing" "$OUT$ERR"
assert_eq "guard read its fields from the shared cache" \
  $'git status --short\nBash' "$(cat "$SEEN")"

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

# --- jq cache: a NUL-bearing payload bypasses the cache ----------------------
nul_payload=$(jq -n '{tool_name:"Bash",tool_input:{command:("git " + ([0] | implode) + "x")}}')
run "$nul_payload" "$TEST_TMPDIR/nul.sh"
assert_eq "NUL flag reaches the guard through the real jq path" "nul=1 cmd=git x" "$(cat "$SEEN")"

# --- jq cache: an un-primed filter falls through to the library --------------
run "$PAYLOAD" "$TEST_TMPDIR/miss.sh"
assert_eq "cache miss serves the right values" $'s-1\nBash' "$(cat "$SEEN")"

# --- --lib preloads a shared library once ------------------------------------
run "$PAYLOAD" --lib lib/powershell/ps-command.sh "$TEST_TMPDIR/lib.sh"
assert_eq "--lib library is loaded before the guards run" "ps=1" "$(cat "$SEEN")"

# --- an unknown guard is reported, the rest still run ------------------------
run "$PAYLOAD" "$TEST_TMPDIR/nope.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "missing guard surfaces as rc 1" 1 "$RC"
assert_contains "missing guard is named" "$ERR" "guard not found"
assert_eq "the other guard still ran" $'git status --short\nBash' "$(cat "$SEEN")"

# --- a real guard decides the same inside the dispatcher as alone ------------
bypass=$(command_json 'git commit --no-verify -m x')
alone_rc=0
alone_err=$(bash "$HOOK_DIR/block-no-verify.sh" <<<"$bypass" 2>&1 >/dev/null) || alone_rc=$?
run "$bypass" --lib lib/powershell/ps-command.sh block-no-verify.sh block-dangerous-git.sh
assert_exit "real guard blocks through the dispatcher" 2 "$RC"
assert_eq "real guard: same exit alone and dispatched" "$alone_rc" "$RC"
assert_eq "real guard: same stderr alone and dispatched" "$alone_err" "$ERR"

# --- hooks.json wires every guard through the dispatcher by file name ---------
for g in secret-pattern-detection hardcoded-path-check block-no-verify block-dangerous-git \
  block-hook-bypass flag-commit-pr-skill-bypass block-noncanonical-commit \
  block-convention-violation block-windows-drive-tmp block-exported-msys-pathconv \
  cli-flag-verify skill-reference-verify stale-path-verify; do
  n=$(jq -r --arg g "$g.sh" '[.hooks[][] | .hooks[] | .command | select(contains("run-guards.sh") and contains(" " + $g))] | length' "$HOOK_DIR/hooks.json")
  if ((n > 0)); then ok "hooks.json dispatches $g"; else bad "hooks.json does not dispatch $g"; fi
  if [[ -f "$HOOK_DIR/$g.sh" ]]; then ok "$g.sh exists on disk"; else bad "$g.sh missing on disk"; fi
done

report
