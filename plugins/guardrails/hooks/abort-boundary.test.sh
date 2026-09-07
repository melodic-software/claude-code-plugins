#!/usr/bin/env bash
# Contract test for hooks/abort-boundary.sh (guardrails plugin, #3528).
#
# Black-box where it matters: every registered hook is run as a subprocess on
# a COPY of the plugin with an abort injected, and the assertions are on exit
# code, stderr, and the stdout document. The registered set is read from
# hooks.json, never enumerated here, so a hook added without the boundary
# fails this suite. Self-contained; no host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$HOOK_DIR/.." && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for these tests" >&2
  exit 1
fi

MARKER='GUARDRAILS_TEST_FORCED_ABORT'
NOTICE='guard did not run (internal error, rc='
# run_hook assigns these through printf -v; declared so ShellCheck sees them.
OUT=""
ERR=""
RC=0

# Insert <line> after the first line of <file> matching <regex>. awk plus a
# rename rather than `sed -i`, whose in-place flag differs between GNU and BSD.
# Fails the suite when the anchor is absent: an injection that silently did
# nothing would make every assertion below vacuous.
inject_after() {
  local file="$1" regex="$2" line="$3" hits
  hits=$(awk -v re="$regex" '$0 ~ re { n++ } END { print n + 0 }' "$file")
  if [[ "$hits" != "1" ]]; then
    bad "inject_after: expected exactly one anchor /$regex/ in ${file##*/}, found $hits"
    return 1
  fi
  awk -v re="$regex" -v ins="$line" '{ print } $0 ~ re && !done { print ins; done = 1 }' \
    "$file" >"$file.injected" && mv "$file.injected" "$file"
}

# pipe_run <payload> <cmd...>: the payload on the command's stdin through a
# pipe (never a here-string; see lib/hook-utils.sh on the 64 KiB deadlock).
pipe_run() {
  local payload="$1"
  shift
  printf '%s' "$payload" | "$@"
}

# run_hook <env NAME=VAL ...> -- <cmd...>: fills OUT, ERR, RC. A fixed benign
# environment: no project dir, telemetry sink unset, both opt-in advisory
# hooks switched on (each exits 0 at its own top line otherwise, before the
# boundary is installed, which is a chosen status and not what this tests).
run_hook() {
  local -a envs=()
  while (($#)) && [[ "$1" != "--" ]]; do
    envs+=("$1")
    shift
  done
  shift
  local rc=0
  # A subshell with exports rather than `env`, which execs a program and so
  # cannot run the pipe_run function.
  (
    unset HOOK_TELEMETRY_SINK
    export CLAUDE_PROJECT_DIR='' \
      CLAUDE_PLUGIN_OPTION_FLAG_COMMIT_PR_SKILL_BYPASS_ENABLED=true \
      CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED=true
    ((${#envs[@]})) && export "${envs[@]}"
    "$@"
  ) >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err" || rc=$?
  OUT=$(cat "$TEST_TMPDIR/out")
  ERR=$(cat "$TEST_TMPDIR/err")
  RC=$rc
}

count_notices() { # <text> -> number of lines carrying the notice
  local n=0 line
  while IFS= read -r line; do
    [[ "$line" == *"$NOTICE"* ]] && n=$((n + 1))
  done < <(printf '%s\n' "$1")
  echo "$n"
}

json_field() { # <document> <jq-path>
  printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
}

BASH_BENIGN=$(jq -nc '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:"git status --short"}}')
BASH_NO_VERIFY=$(jq -nc '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:"git commit --no-verify -m x"}}')
BASH_FORCE_PUSH=$(jq -nc '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:"git push --force origin main"}}')

# --- The registered hook set, read from hooks.json --------------------------
# Every command is tokenised; `--lib <path>` pairs are dropped (a library, not
# a hook); every remaining *.sh token is a registered script, the dispatcher
# included. EVENTS records the event(s) each script is registered under, which
# the forced-abort assertions below compare against the notice's hookEventName.
declare -A EVENTS=()
REGISTERED=()
set -f
while IFS=$'\t' read -r ev cmd; do
  # shellcheck disable=SC2206  # the split IS the point; globbing is off
  toks=($cmd)
  skip=0
  for tok in "${toks[@]}"; do
    if ((skip)); then
      skip=0
      continue
    fi
    if [[ "$tok" == "--lib" ]]; then
      skip=1
      continue
    fi
    [[ "$tok" == *.sh ]] || continue
    name="${tok##*/}"
    if [[ -z "${EVENTS[$name]:-}" ]]; then
      REGISTERED+=("$name")
      EVENTS[$name]=" $ev "
    elif [[ "${EVENTS[$name]}" != *" $ev "* ]]; then
      EVENTS[$name]+="$ev "
    fi
  done
done < <(jq -r '.hooks | to_entries[] | .key as $ev | .value[] | .hooks[] | "\($ev)\t\(.command)"' "$HOOK_DIR/hooks.json")
set +f

# A parse that quietly found nothing would make the whole suite pass on an
# empty loop. The set is fourteen guards plus the dispatcher today; the floor
# is loose on purpose so removing a guard is not a failure here.
if ((${#REGISTERED[@]} >= 10)); then
  ok "hooks.json yields a registered set of ${#REGISTERED[@]} scripts"
else
  bad "hooks.json yielded only ${#REGISTERED[@]} scripts: ${REGISTERED[*]}"
fi
for name in "${REGISTERED[@]}"; do
  [[ -f "$HOOK_DIR/$name" ]] || bad "registered script missing from hooks/: $name"
done

# --- Static: every registered script installs the boundary ------------------
for name in "${REGISTERED[@]}"; do
  stem="${name%.sh}"
  if grep -qE '^source "[$](_HOOK_SELF|_RG_DIR)/abort-boundary.sh"$' "$HOOK_DIR/$name"; then
    ok "$name sources abort-boundary.sh"
  else
    bad "$name does not source abort-boundary.sh"
  fi
  if grep -qE "^guard::abort_boundary ${stem} (\"\"|[A-Za-z]+) (open|closed)( [0-9]+)+\$" "$HOOK_DIR/$name"; then
    ok "$name installs the boundary under its own name with a declared posture"
  else
    bad "$name has no 'guard::abort_boundary $stem <event> <open|closed> <status>...' line"
  fi
  if grep -qE '^source "[$](_HOOK_SELF|_RG_DIR)/hook-utils.sh" \|\| exit 70' "$HOOK_DIR/$name"; then
    ok "$name treats a failed hook-utils.sh load as an abort"
  else
    bad "$name still falls through a failed hook-utils.sh load"
  fi
  if grep -Fq "$MARKER" "$HOOK_DIR/$name"; then
    bad "shipped $name must not honor $MARKER"
  fi
done

# --- Forced abort in EVERY registered guard, on a copy of the plugin --------
# The injection is an unbound-variable expansion right after the install line:
# the real `set -u` abort path, at the point every guard reaches on every fire.
# Expected on each: exit 0 (the declared fail-open posture), one stderr line
# naming the guard and the status, and one hook JSON document on stdout whose
# systemMessage and additionalContext carry the same text and whose
# hookEventName is an event the guard is registered for.
COPY="$TEST_TMPDIR/plugin"
cp -R "$PLUGIN_DIR" "$COPY"
for name in "${REGISTERED[@]}"; do
  [[ "$name" == run-guards.sh ]] && continue
  stem="${name%.sh}"
  inject_after "$COPY/hooks/$name" "^guard::abort_boundary ${stem} " \
    ": \"\${${MARKER}?forced abort}\"" || continue
  run_hook CLAUDE_PLUGIN_ROOT="$COPY" OSTYPE=msys -- pipe_run "$BASH_BENIGN" bash "$COPY/hooks/$name"
  assert_exit "$stem: forced abort exits with the declared fail-open posture" 0 "$RC"
  assert_contains "$stem: stderr names the guard and the status" "$ERR" \
    "guardrails ${stem}: ${NOTICE}1); fail-open"
  assert_eq "$stem: exactly one notice line on stderr" 1 "$(count_notices "$ERR")"
  if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then
    ok "$stem: stdout is one JSON document"
  else
    bad "$stem: stdout is not a JSON document: $OUT"
  fi
  assert_contains "$stem: systemMessage names the guard" \
    "$(json_field "$OUT" .systemMessage)" "guardrails ${stem}: ${NOTICE}"
  assert_contains "$stem: additionalContext names the guard" \
    "$(json_field "$OUT" .hookSpecificOutput.additionalContext)" "guardrails ${stem}: ${NOTICE}"
  ev_out=$(json_field "$OUT" .hookSpecificOutput.hookEventName)
  if [[ -n "$ev_out" && "${EVENTS[$name]}" == *" $ev_out "* ]]; then
    ok "$stem: hookEventName ($ev_out) is an event the guard is registered for"
  else
    bad "$stem: hookEventName '$ev_out' is not among registered events (${EVENTS[$name]})"
  fi
done

# --- Mid-hook abort through a shared helper that fails ----------------------
# Deeper than the prologue: hook-utils.sh has loaded and stdin has been read
# when a shared helper, redefined to trip an unbound expansion, aborts the
# guard. One blocking hook (hook::jq_fields) on a payload it would otherwise
# DENY, one advisory hook (hook::require_jq) on its normal PostToolUse payload.
MID="$TEST_TMPDIR/mid"
cp -R "$PLUGIN_DIR" "$MID"
inject_after "$MID/hooks/block-windows-drive-tmp.sh" '^source "[$]_HOOK_SELF/hook-utils.sh"' \
  "hook::jq_fields() { : \"\${${MARKER}?forced abort in hook::jq_fields}\"; }"
run_hook CLAUDE_PLUGIN_ROOT="$MID" OSTYPE=msys -- \
  pipe_run "$(write_json 'D:/tmp/x' 'body')" bash "$MID/hooks/block-windows-drive-tmp.sh"
assert_exit "block-windows-drive-tmp: helper failure after stdin fails open (declared posture)" 0 "$RC"
assert_contains "block-windows-drive-tmp: helper failure is named on stderr" "$ERR" \
  "guardrails block-windows-drive-tmp: ${NOTICE}1); fail-open"
assert_eq "block-windows-drive-tmp: helper failure emits hookEventName PreToolUse" PreToolUse \
  "$(json_field "$OUT" .hookSpecificOutput.hookEventName)"
# The same payload on the shipped guard is a deny, which is what makes the
# fail-open above a documented, visible allow rather than a silent one.
run_hook OSTYPE=msys -- pipe_run "$(write_json 'D:/tmp/x' 'body')" bash "$HOOK_DIR/block-windows-drive-tmp.sh"
assert_exit "block-windows-drive-tmp: shipped guard still denies D:/tmp" 2 "$RC"
assert_absent "block-windows-drive-tmp: a deny carries no abort notice" "$ERR$OUT" "$NOTICE"

inject_after "$MID/hooks/cli-flag-verify.sh" '^source "[$]_HOOK_SELF/hook-utils.sh"' \
  "hook::require_jq() { : \"\${${MARKER}?forced abort in hook::require_jq}\"; }"
mkdir -p "$TEST_TMPDIR/data"
run_hook CLAUDE_PLUGIN_ROOT="$MID" CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data" -- \
  pipe_run "$(write_json "$TEST_TMPDIR/notes.md" 'run git status')" bash "$MID/hooks/cli-flag-verify.sh"
assert_exit "cli-flag-verify: helper failure after stdin fails open (declared posture)" 0 "$RC"
assert_contains "cli-flag-verify: helper failure is named on stderr" "$ERR" \
  "guardrails cli-flag-verify: ${NOTICE}1); fail-open"
assert_eq "cli-flag-verify: helper failure emits hookEventName PostToolUse" PostToolUse \
  "$(json_field "$OUT" .hookSpecificOutput.hookEventName)"

# --- Dispatched: an aborting guard neither masks a sibling's deny nor hides --
DISPATCH="$HOOK_DIR/run-guards.sh"
ABORTING="$COPY/hooks/block-no-verify.sh" # injected above
run_hook -- pipe_run "$BASH_FORCE_PUSH" bash "$DISPATCH" "$ABORTING" "$HOOK_DIR/block-dangerous-git.sh"
assert_exit "dispatched: sibling deny still wins the exit code beside an aborting guard" 2 "$RC"
assert_contains "dispatched: the abort notice is on stderr next to the deny" "$ERR" \
  "guardrails block-no-verify: ${NOTICE}"
assert_contains "dispatched: the sibling's deny reason is on stderr" "$ERR" "BLOCKED"

run_hook -- pipe_run "$BASH_BENIGN" bash "$DISPATCH" "$ABORTING" "$HOOK_DIR/block-dangerous-git.sh"
assert_exit "dispatched: benign call with one aborting guard exits 0" 0 "$RC"
assert_contains "dispatched: benign call carries the notice as systemMessage" \
  "$(json_field "$OUT" .systemMessage)" "guardrails block-no-verify: ${NOTICE}"
assert_eq "dispatched: notice hookEventName survives the dispatcher" PreToolUse \
  "$(json_field "$OUT" .hookSpecificOutput.hookEventName)"

# Two aborting guards: the dispatcher merges both notices into ONE document.
run_hook -- pipe_run "$BASH_BENIGN" bash "$DISPATCH" "$ABORTING" "$COPY/hooks/block-dangerous-git.sh"
assert_exit "dispatched: two aborting guards exit 0" 0 "$RC"
assert_eq "dispatched: two notices merge into one document" 1 "$(printf '%s\n' "$OUT" | jq -c . 2>/dev/null | grep -c .)"
merged_sys=$(json_field "$OUT" .systemMessage)
assert_contains "dispatched: merged systemMessage names the first guard" "$merged_sys" "guardrails block-no-verify:"
assert_contains "dispatched: merged systemMessage names the second guard" "$merged_sys" "guardrails block-dangerous-git:"

# --- The dispatcher's own boundary ------------------------------------------
# Before stdin: the event is not known yet, so the notice is systemMessage
# only. After priming: the event read from the payload names the block. A
# deliberate aggregated status (a stub's 3) is released, not reported.
RG_EARLY="$TEST_TMPDIR/rg-early"
cp -R "$PLUGIN_DIR" "$RG_EARLY"
inject_after "$RG_EARLY/hooks/run-guards.sh" '^guard::abort_boundary run-guards ' ": \"\${${MARKER}?forced abort}\""
run_hook -- pipe_run "$BASH_FORCE_PUSH" bash "$RG_EARLY/hooks/run-guards.sh" block-dangerous-git.sh
assert_exit "dispatcher abort before stdin fails open (declared posture)" 0 "$RC"
assert_contains "dispatcher abort before stdin names run-guards" "$ERR" "guardrails run-guards: ${NOTICE}1); fail-open"
assert_contains "dispatcher abort before stdin carries systemMessage" \
  "$(json_field "$OUT" .systemMessage)" "guardrails run-guards:"
assert_eq "dispatcher abort before stdin has no hookSpecificOutput (event unknown)" "" \
  "$(json_field "$OUT" .hookSpecificOutput)"

RG_LATE="$TEST_TMPDIR/rg-late"
cp -R "$PLUGIN_DIR" "$RG_LATE"
inject_after "$RG_LATE/hooks/run-guards.sh" '^# --- run -{3,}' ": \"\${${MARKER}?forced abort}\""
run_hook -- pipe_run "$BASH_FORCE_PUSH" bash "$RG_LATE/hooks/run-guards.sh" block-dangerous-git.sh
assert_exit "dispatcher abort after priming fails open (declared posture)" 0 "$RC"
assert_eq "dispatcher abort after priming names the event from the payload" PreToolUse \
  "$(json_field "$OUT" .hookSpecificOutput.hookEventName)"

printf '#!/usr/bin/env bash\nexit 3\n' >"$TEST_TMPDIR/three.sh"
run_hook -- pipe_run "$BASH_BENIGN" bash "$DISPATCH" "$TEST_TMPDIR/three.sh"
assert_exit "dispatcher: a guard's deliberate 3 is aggregated, not reported as an abort" 3 "$RC"
assert_absent "dispatcher: released boundary emits no notice for the aggregated status" "$ERR$OUT" "$NOTICE"

# --- Transparency: chosen statuses pass through with no notice --------------
run_hook -- pipe_run "$BASH_NO_VERIFY" bash "$HOOK_DIR/block-no-verify.sh"
assert_exit "shipped block-no-verify still denies --no-verify" 2 "$RC"
assert_absent "a deny carries no abort notice" "$ERR$OUT" "$NOTICE"
assert_silent "a deny writes nothing to stdout" "$OUT"
run_hook -- pipe_run "$BASH_BENIGN" bash "$HOOK_DIR/block-no-verify.sh"
assert_exit "shipped block-no-verify still allows a benign command" 0 "$RC"
assert_silent "an allow is silent" "$ERR$OUT"
run_hook CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED=false -- pipe_run "$BASH_NO_VERIFY" bash "$HOOK_DIR/block-no-verify.sh"
assert_exit "kill switch exit 0 (hook::check_enabled) passes through" 0 "$RC"
assert_silent "kill switch exit is silent" "$ERR$OUT"
run_hook CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data" -- \
  pipe_run "$(write_json "$TEST_TMPDIR/notes.md" 'plain prose')" bash "$HOOK_DIR/cli-flag-verify.sh"
assert_exit "shipped cli-flag-verify exits 0 on plain prose" 0 "$RC"
assert_absent "an advisory hook's normal run carries no abort notice" "$ERR$OUT" "$NOTICE"

# --- The helper itself, through stubs -----------------------------------------
stub() { # stub <name> <body...>: a script that sources the boundary first
  local name="$1"
  shift
  {
    printf '#!/usr/bin/env bash\nset -uo pipefail\nsource "%s/abort-boundary.sh"\n' "$HOOK_DIR"
    printf '%s\n' "$@"
  } >"$TEST_TMPDIR/$name"
}
for code in 0 2; do
  stub "pass$code.sh" 'guard::abort_boundary stub-pass PreToolUse open 0 2' "exit $code"
  run_hook -- bash "$TEST_TMPDIR/pass$code.sh"
  assert_exit "chosen status $code passes through unchanged" "$code" "$RC"
  assert_silent "chosen status $code produces no output" "$ERR$OUT"
done
for code in 1 3 70 127; do
  stub "conv$code.sh" 'guard::abort_boundary stub-conv PreToolUse open 0 2' "exit $code"
  run_hook -- bash "$TEST_TMPDIR/conv$code.sh"
  assert_exit "unchosen status $code becomes the open posture (0)" 0 "$RC"
  assert_contains "unchosen status $code is named" "$ERR" "guardrails stub-conv: ${NOTICE}${code}); fail-open"
done
stub "closed.sh" 'guard::abort_boundary stub-closed PreToolUse closed 0 2' 'exit 3'
run_hook -- bash "$TEST_TMPDIR/closed.sh"
assert_exit "closed posture turns an abort into a block (2)" 2 "$RC"
assert_contains "closed posture names itself on stderr" "$ERR" "guardrails stub-closed: ${NOTICE}3); fail-closed"
assert_silent "closed posture writes no stdout document (stdout is not read on exit 2)" "$OUT"
stub "closed-pass.sh" 'guard::abort_boundary stub-closed PreToolUse closed 0 2' 'exit 0'
run_hook -- bash "$TEST_TMPDIR/closed-pass.sh"
assert_exit "closed posture still passes a chosen 0 through" 0 "$RC"
assert_silent "closed posture chosen 0 is silent" "$ERR$OUT"
stub "released.sh" 'guard::abort_boundary stub-rel PreToolUse open 0 2' 'guard::abort_boundary_release' 'exit 3'
run_hook -- bash "$TEST_TMPDIR/released.sh"
assert_exit "released boundary lets 3 through" 3 "$RC"
assert_silent "released boundary is silent" "$ERR$OUT"
stub "noevent.sh" 'guard::abort_boundary stub-noev "" open 0' 'exit 1'
run_hook -- bash "$TEST_TMPDIR/noevent.sh"
assert_exit "empty event: still the open posture" 0 "$RC"
assert_eq "empty event: systemMessage only" "" "$(json_field "$OUT" .hookSpecificOutput)"
assert_contains "empty event: systemMessage present" "$(json_field "$OUT" .systemMessage)" "guardrails stub-noev:"
stub "badposture.sh" 'guard::abort_boundary stub-bad PreToolUse maybe 0 2' 'exit 1'
run_hook -- bash "$TEST_TMPDIR/badposture.sh"
assert_exit "unknown posture word falls back to open" 0 "$RC"
assert_contains "unknown posture word is named at install" "$ERR" "posture maybe is not open or closed; using open"
stub "quote.sh" 'guard::abort_boundary "stub-\"q\"" PreToolUse open 0' 'exit 1'
run_hook -- bash "$TEST_TMPDIR/quote.sh"
if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then
  ok "a quote in the hook name is escaped into valid JSON"
else
  bad "a quote in the hook name broke the document: $OUT"
fi
# Under set -u an unbound expansion is the realistic abort; the stub proves
# the trap fires for it (not only for an explicit exit) and reports rc 1.
# shellcheck disable=SC2016  # the stub body must carry a literal, unexpanded $
stub "unbound.sh" 'guard::abort_boundary stub-unbound PreToolUse open 0 2' ': "$STUB_UNBOUND_VARIABLE"' 'exit 0'
run_hook -- bash "$TEST_TMPDIR/unbound.sh"
assert_exit "set -u abort in a stub fails open" 0 "$RC"
assert_contains "set -u abort in a stub is named with rc=1" "$ERR" "guardrails stub-unbound: ${NOTICE}1); fail-open"

# --- The handler cannot re-enter ----------------------------------------------
# The handler's first act is `trap - EXIT`. When its own body then fails (an
# unbound expansion, or an exit) the process ends once, with the stderr line
# already written; a second notice would mean the trap ran again. On the
# unbound case bash keeps the status that was pending when the trap fired (the
# stub's 3), so the fail-open exit 0 never happens: loud, once, and not 0.
# shellcheck disable=SC2016  # the stub body must carry a literal, unexpanded $
stub "reenter-unbound.sh" 'guard::abort_boundary stub-reenter PreToolUse open 0 2' \
  'guard::_abort_json_escape_to() { : "${STUB_HANDLER_BODY_FAILURE?handler body failure}"; }' \
  'exit 3'
run_hook -- bash "$TEST_TMPDIR/reenter-unbound.sh"
assert_eq "handler body failure (unbound): exactly one notice line" 1 "$(count_notices "$ERR")"
assert_contains "handler body failure (unbound): bash's own error follows the notice" "$ERR" "handler body failure"
assert_exit "handler body failure (unbound): the pending status ends the process, no loop, no fail-open" 3 "$RC"
assert_silent "handler body failure (unbound): no half-built document on stdout" "$OUT"
stub "reenter-exit.sh" 'guard::abort_boundary stub-reenter PreToolUse open 0 2' \
  'guard::_abort_json_escape_to() { exit 99; }' \
  'exit 3'
run_hook -- bash "$TEST_TMPDIR/reenter-exit.sh"
assert_eq "handler body exit: exactly one notice line" 1 "$(count_notices "$ERR")"
assert_exit "handler body exit: that exit is final" 99 "$RC"

report
