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
# test-scope: plugins/guardrails/hooks/*.sh plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/hooks/hooks.json plugins/guardrails/prerequisites.json
# shellcheck disable=SC2016
set -uo pipefail

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/run-guards-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="$HOOK_DIR/run-guards.sh"
# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
export CLAUDE_CODE_SESSION_ATTENDED=0
unset GUARDRAILS_SESSION_UNWATCHED
jq_crlf_free

export CLAUDE_PLUGIN_ROOT="$HOOK_DIR/.."
export CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for these tests" >&2
  exit 1
fi

if declare -F jq >/dev/null; then
  jq() { MSYS_NO_PATHCONV=1 command jq --binary "$@"; }
fi
HOOKS_JSON="$HOOK_DIR/hooks.json"
if command -v cygpath >/dev/null 2>&1; then HOOKS_JSON=$(cygpath -m "$HOOKS_JSON"); fi

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
stub deny.sh 'hook::emit_document "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"stub deny\"}}"'
stub ask.sh 'hook::emit_document "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\": \"ask\"}}"'
stub ask1.sh 'hook::emit_document "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"ask one\"}}"'
stub ask2.sh 'hook::emit_document "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"ask two\"}}"'

PAYLOAD=$(jq -n '{session_id:"s-1",tool_name:"Bash",cwd:"/x",tool_input:{command:"git status --short"}}')

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

run "$PAYLOAD" "$TEST_TMPDIR/allow.sh"
assert_exit "allow-only exits 0" 0 "$RC"
assert_silent "allow-only prints nothing" "$OUT$ERR"
assert_eq "guard read its fields from the shared cache" \
  $'git status --short\nBash' "$(cat "$SEEN")"

run "$PAYLOAD" "$TEST_TMPDIR/dest.sh"
assert_exit "dest-named dest exits 0" 0 "$RC"
assert_contains "dest-named dest received the payload" "$(cat "$SEEN")" 'tool_name'

run "$PAYLOAD" "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "block wins the exit code" 2 "$RC"
assert_contains "block reason reaches stderr" "$ERR" "BLOCKED: stub"
assert_eq "the guard after the block still ran" $'git status --short\nBash' "$(cat "$SEEN")"

run "$PAYLOAD" "$TEST_TMPDIR/crash.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "highest non-block code surfaces" 3 "$RC"
run "$PAYLOAD" "$TEST_TMPDIR/crash.sh" "$TEST_TMPDIR/block.sh"
assert_exit "2 dominates a higher non-block code" 2 "$RC"

standalone=$(bash "$TEST_TMPDIR/ctx1.sh" <<<"$PAYLOAD")
run "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh"
assert_eq "single emitter is passed through verbatim" "$standalone" "$OUT"

run "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/ctx2.sh"
assert_exit "merge run exits 0" 0 "$RC"
assert_eq "merged output is exactly one JSON document" "1" "$(jq -s 'length' <<<"$OUT")"
merged_ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT")
merged_ctx="${merged_ctx//$'\r'/}" # the Windows jq build writes CRLF
assert_eq "merged additionalContext carries both guards, in order" $'ctx one\n\nctx two' "$merged_ctx"
assert_eq "merged hookEventName kept" "PreToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$OUT")"
assert_eq "merged systemMessage carries the one guard that set it" "sys two" "$(jq -r '.systemMessage' <<<"$OUT")"

hsd() { jq -r ".hookSpecificOutput.$1 // empty" <<<"$OUT" | tr -d '\r'; }
run "$PAYLOAD" "$TEST_TMPDIR/ask1.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "ask beside a silent guard exits 0" 0 "$RC"
assert_eq "ask beside a silent guard: the decision is ask" ask "$(hsd permissionDecision)"
run "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/ask1.sh"
assert_eq "ask beside a context document: the decision is ask" ask "$(hsd permissionDecision)"
assert_eq "ask beside a context document: the context is kept" "ctx one" "$(hsd additionalContext)"
assert_eq "ask beside a context document: one document" "1" "$(jq -s 'length' <<<"$OUT")"
run "$PAYLOAD" "$TEST_TMPDIR/ask1.sh" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/ask2.sh"
assert_eq "two asks: the decision is ask" ask "$(hsd permissionDecision)"
assert_eq "two asks: both reasons, in order" $'ask one\n\nask two' "$(hsd permissionDecisionReason)"
run "$PAYLOAD" "$TEST_TMPDIR/ask1.sh" "$TEST_TMPDIR/deny.sh"
assert_eq "ask beside a deny document: the decision is deny" deny "$(hsd permissionDecision)"
assert_eq "ask beside a deny document: the deny reason only" "stub deny" "$(hsd permissionDecisionReason)"
run "$PAYLOAD" "$TEST_TMPDIR/ask1.sh" "$TEST_TMPDIR/block.sh"
assert_exit "ask beside a guard that exits 2: the call is denied" 2 "$RC"
assert_absent "ask beside a guard that exits 2: no ask on stdout" "$OUT" '"ask"'
run "$PAYLOAD" "$TEST_TMPDIR/ask1.sh" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/block.sh"
assert_exit "ask and context beside an exit 2: denied" 2 "$RC"
assert_absent "ask and context beside an exit 2: the ask is dropped" "$OUT" '"ask"'

ATT_TOP=$(git -C "$HOOK_DIR" rev-parse --show-toplevel)
ATT_TOP="${ATT_TOP//$'\r'/}"
mkdir -p "$ATT_TOP/.work"
ATT_REPO=$(mktemp -d "$ATT_TOP/.work/run-guards-att.XXXXXX")
trap 'rm -rf "$TEST_TMPDIR" "$ATT_REPO"' EXIT
git init -q "$ATT_REPO"
att_run() {
  local p
  p=$(jq -nc --arg c "$2" --arg d "$ATT_REPO" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
  RC=0
  OUT=$(env CLAUDE_CODE_SESSION_ATTENDED="$1" bash "$DISPATCH" --lib lib/powershell/ps-command.sh \
    block-no-verify.sh block-dangerous-git.sh block-noncanonical-commit.sh \
    block-root-delete-target.sh block-credential-read.sh <<<"$p" 2>"$TEST_TMPDIR/err") || RC=$?
  ERR=$(cat "$TEST_TMPDIR/err")
}
att_run 1 'git reset --hard'
assert_exit "attended: git reset --hard exits 0 to ask" 0 "$RC"
assert_eq "attended: git reset --hard asks" ask "$(hsd permissionDecision)"
assert_contains "attended: the ask names the form" "$(hsd permissionDecisionReason)" "git reset --hard discards uncommitted work"
att_run 1 'git reset --hard && rm -rf /'
assert_eq "attended: two refusing guards ask once" ask "$(hsd permissionDecision)"
assert_contains "attended: the joined reason names the delete too" "$(hsd permissionDecisionReason)" "filesystem root"
att_run 1 'git reset --hard; git commit --no-verify -m x'
assert_exit "attended: a guard that denies outright still denies" 2 "$RC"
att_run 0 'git reset --hard'
assert_exit "unattended: git reset --hard denies" 2 "$RC"
assert_absent "unattended: no ask document" "$OUT" '"ask"'
rg_many=""
for ((rg_i = 1; rg_i <= 600; rg_i++)); do rg_many+=" a$rg_i"; done
rg_cds=""
for ((rg_i = 1; rg_i <= 40; rg_i++)); do rg_cds+="; cd x"; done
rg_hops=""
for ((rg_i = 1; rg_i <= 141; rg_i++)); do rg_hops+=" -c alias.a$rg_i=a$((rg_i + 1))"; done
att_run 1 "rm -rf \"\$X\"; rm -rf$rg_many"
assert_exit "attended row: a bare variable, then past the target budget, denies" 2 "$RC"
att_run 1 "rm -rf /; rm -rf$rg_many"
assert_exit "attended row: a root, then past the target budget, denies" 2 "$RC"
att_run 1 "rm -rf /$rg_cds; rm -rf x"
assert_exit "attended row: a root, then past the directory-change budget, denies" 2 "$RC"
att_run 1 "git reset --hard; git$rg_hops a1"
assert_exit "attended row: reset --hard, then past the alias budget, denies" 2 "$RC"
assert_contains "attended row: the alias budget reason is on stderr" "$ERR" "over 128 re-expansions"
if (ulimit -s 1024) 2>/dev/null; then
  att_p=$(jq -nc --arg c "git reset --hard; git$rg_hops a1" --arg d "$ATT_REPO" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
  RC=0
  OUT=$(
    ulimit -s 1024
    env CLAUDE_CODE_SESSION_ATTENDED=1 bash "$DISPATCH" --lib lib/powershell/ps-command.sh \
      block-no-verify.sh block-dangerous-git.sh block-noncanonical-commit.sh \
      block-root-delete-target.sh block-credential-read.sh <<<"$att_p" 2>/dev/null
  ) || RC=$?
  assert_exit "attended row, 1 MB stack: reset --hard, then past the alias budget, denies" 2 "$RC"
fi
alias_p=$(jq -nc --arg c "git$rg_hops a1" --arg d "$ATT_REPO" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
for rg_stack in default 1024; do
  if [[ "$rg_stack" != default ]] && ! (ulimit -s "$rg_stack") 2>/dev/null; then continue; fi
  RC=0
  ERR=$(
    [[ "$rg_stack" == default ]] || ulimit -s "$rg_stack"
    bash "$DISPATCH" --lib lib/powershell/ps-command.sh \
      block-no-verify.sh block-dangerous-git.sh block-noncanonical-commit.sh \
      block-root-delete-target.sh block-credential-read.sh <<<"$alias_p" 2>&1 >/dev/null
  ) || RC=$?
  assert_exit "alias chain past the budget, $rg_stack stack: denies" 2 "$RC"
  assert_contains "alias chain past the budget, $rg_stack stack: the reason is on stderr" "$ERR" "over 128 re-expansions"
done
att_run 1 'rm -rf "$X"; rm -rf /etc/foo'
assert_eq "attended row: two asking segments ask" ask "$(hsd permissionDecision)"
assert_contains "attended row: the reason names the bare variable" "$(hsd permissionDecisionReason)" "bare variable"
assert_contains "attended row: the reason names the outside-tree delete" "$(hsd permissionDecisionReason)" "/etc/foo"
att_run 1 'git status'
assert_exit "attended: an unrelated command passes" 0 "$RC"
assert_silent "attended: an unrelated command prints nothing" "$OUT$ERR"

run "" "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/block.sh"
assert_exit "empty stdin: every guard's empty-stdin skip, taken once" 0 "$RC"
assert_silent "empty stdin prints nothing" "$OUT$ERR"
run "not json" "$TEST_TMPDIR/allow.sh"
assert_exit "malformed stdin: a fail-closed guard's rc-2 path is reached" 2 "$RC"
assert_contains "malformed stdin names the reason once" "$ERR" "not valid JSON"
assert_eq "malformed-stdin reason printed exactly once" "1" "$(grep -c 'not valid JSON' <<<"$ERR")"

CUT_PREFIX='{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify'
run "$CUT_PREFIX" "$TEST_TMPDIR/allow.sh" "$TEST_TMPDIR/block.sh"
assert_exit "cut-short stdin (early EOF): loud allow, taken once" 0 "$RC"
assert_contains "cut-short stdin (early EOF): the lib diagnostic names the cause" "$ERR" "cut short"
assert_absent "cut-short stdin (early EOF): nothing is BLOCKED" "$ERR" "BLOCKED"
assert_eq "cut-short stdin (early EOF): exactly one JSON document on stdout" "1" "$(jq -s 'length' <<<"$OUT")"
assert_contains "cut-short stdin (early EOF): systemMessage carries the notice" "$(jq -r '.systemMessage' <<<"$OUT")" "ran unchecked"
assert_eq "cut-short stdin (early EOF): notice printed exactly once" "1" "$(grep -c 'ran unchecked' <<<"$ERR")"
assert_eq "cut-short stdin (early EOF): no guard ran" "" "$(cat "$SEEN")"
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

nul_payload=$(jq -n '{tool_name:"Bash",tool_input:{command:("git " + ([0] | implode) + "x")}}')
run "$nul_payload" "$TEST_TMPDIR/nul.sh"
assert_eq "NUL flag reaches the guard through the real jq path" "nul=1 cmd=git x" "$(cat "$SEEN")"

run "$PAYLOAD" "$TEST_TMPDIR/miss.sh"
assert_eq "cache miss serves the right values" $'s-1\nBash' "$(cat "$SEEN")"

run "$PAYLOAD" --lib lib/powershell/ps-command.sh "$TEST_TMPDIR/lib.sh"
assert_eq "--lib is skipped on a Bash payload" "ps=unset" "$(cat "$SEEN")"
PWSH_PAYLOAD=$(jq -n '{session_id:"s-1",tool_name:"PowerShell",cwd:"/x",tool_input:{command:"git status --short"}}')
run "$PWSH_PAYLOAD" --lib lib/powershell/ps-command.sh "$TEST_TMPDIR/lib.sh"
assert_eq "--lib library is loaded on a PowerShell payload" "ps=1" "$(cat "$SEEN")"

run "$PAYLOAD" "$TEST_TMPDIR/dirname.sh"
assert_eq "dirname inside a dispatched guard is the external command" "file /" "$(cat "$SEEN")"

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
    block-no-verify.sh block-dangerous-git.sh \
    flag-commit-pr-skill-bypass.sh block-noncanonical-commit.sh \
    block-convention-violation.sh block-windows-drive-tmp.sh \
    block-exported-msys-pathconv.sh <<<"$PAYLOAD" >/dev/null
  assert_eq "benign Bash dispatcher spends one jq (the shared parse), no dirname or sed" "jq" "$(cat "$SPAWN_LOG")"
fi
DISPATCH_XTRACE=$(PS4='+PID=$BASHPID ' bash -x "$DISPATCH" --lib lib/powershell/ps-command.sh \
  block-no-verify.sh block-dangerous-git.sh \
  flag-commit-pr-skill-bypass.sh block-noncanonical-commit.sh \
  block-convention-violation.sh block-windows-drive-tmp.sh \
  block-exported-msys-pathconv.sh <<<"$PAYLOAD" 2>&1 >/dev/null) || true
assert_absent "benign Bash dispatcher never sources ps-command.sh" \
  "$DISPATCH_XTRACE" "ps-command.sh"
assert_eq "benign Bash dispatcher forks only the shared parse (five BASHPIDs in the xtrace)" \
  "5" "$(grep -o 'PID=[0-9]*' <<<"$DISPATCH_XTRACE" | sort -u | wc -l | tr -d ' ')"
# --- a parse seeded by exec-bash.mjs --bps-seed --------------------------------
# The pair is trusted only under --bps-seeded, which only the hooks.json row
# passes. A forged pair that gives a refused command the list of a benign one is
# ignored without the flag, and a seeded call runs no shfmt or jq in bash.
# shellcheck disable=SC2016  # the child shell expands these
seed_list() { bash -c 'source "$1/hook-utils.sh"; hook::_bps_shfmt_to l "$2" && printf %s "$l"' -- "$HOOK_DIR" "$1"; }
LS_LIST=$(seed_list 'ls')
att_seed() {
  local p
  p=$(jq -nc --arg c "$2" --arg d "$ATT_REPO" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
  RC=0
  OUT=$(env CLAUDE_CODE_SESSION_ATTENDED=1 HOOK_BPS_SEED_KEY="$3" HOOK_BPS_SEED_VAL="$4" PATH="$SHIM:$PATH" \
    bash "$DISPATCH" ${1:+"$1"} --lib lib/powershell/ps-command.sh \
    block-no-verify.sh block-dangerous-git.sh block-noncanonical-commit.sh \
    block-root-delete-target.sh block-credential-read.sh <<<"$p" 2>"$TEST_TMPDIR/err") || RC=$?
}
if [[ -n "$LS_LIST" && -x "$SHIM/jq" ]]; then
  att_seed "" 'git reset --hard' 'git reset --hard' "$LS_LIST"
  assert_eq "a forged seed without --bps-seeded is ignored: reset --hard still asks" ask "$(hsd permissionDecision)"
  : >"$SPAWN_LOG"
  att_seed --bps-seeded 'git status' 'git status' "$(seed_list 'git status')"
  assert_eq "a seeded call allows as before" "" "$(hsd permissionDecision)"
  assert_eq "a seeded call runs no jq in bash (no parse)" "" "$(cat "$SPAWN_LOG")"
  : >"$SPAWN_LOG"
  att_seed --bps-seeded 'git reset --hard' 'git status' "$(seed_list 'git status')"
  assert_eq "a seed keyed to other text is not used: reset --hard asks" ask "$(hsd permissionDecision)"
  assert_eq "a seed keyed to other text: bash parses (one jq)" "jq" "$(cat "$SPAWN_LOG")"
else
  bad "need the seed list and the jq shim to test --bps-seeded"
fi
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
  printf '#!/usr/bin/env bash\nprintf "git %%s\\n" "$*" >>%q\nexec %q "$@"\n' \
    "$SPAWN_LOG" "$(type -P git)" >"$SHIM/git"
  # Git Bash resolves `git` to `git.exe` via PATHEXT. A shim named only `git`
  # is skipped and the rev-parse count stays 0 (#4527).
  cp "$SHIM/git" "$SHIM/git.exe"
  chmod +x "$SHIM/realpath" "$SHIM/git" "$SHIM/git.exe"
  : >"$SPAWN_LOG"
  PATH="$SHIM:$PATH" CLAUDE_PROJECT_DIR="$PV_REPO" bash "$DISPATCH" \
    cli-flag-verify.sh skill-reference-verify.sh stale-path-verify.sh <<<"$PV_PAYLOAD" >/dev/null 2>&1
  assert_eq "post-verify dispatcher: no jq outside a marketplace repo" \
    "0" "$(grep -cx jq "$SPAWN_LOG")"
  want_realpath=1
  [[ "$OSTYPE" == linux* ]] && want_realpath=0
  assert_eq "post-verify dispatcher: $want_realpath realpath for the three path reads" \
    "$want_realpath" "$(grep -cx realpath "$SPAWN_LOG")"
  assert_eq "post-verify dispatcher: one git rev-parse for the three root reads" \
    "1" "$(grep -c 'rev-parse --show-toplevel' "$SPAWN_LOG")"
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
for g in block-no-verify block-dangerous-git \
  flag-commit-pr-skill-bypass block-noncanonical-commit \
  block-convention-violation block-windows-drive-tmp block-exported-msys-pathconv \
  secret-pattern-detection hardcoded-path-check \
  cli-flag-verify skill-reference-verify stale-path-verify \
  workflow-resilience-check; do
  assert_absent "$g sources hook-utils without dirname" "$(cat "$HOOK_DIR/$g.sh")" \
    'source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"'
done

NOJQ_PATH=""
NOJQ_LN_FAILED=""
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
      if ! MSYS=winsymlinks:nativestrict ln -s "$f" "$shim/$base"; then
        NOJQ_LN_FAILED="$f"
        break
      fi
    done
    [[ -z "$NOJQ_LN_FAILED" ]] || break
    NOJQ_PATH+="${NOJQ_PATH:+:}$shim"
  else
    NOJQ_PATH+="${NOJQ_PATH:+:}$d"
  fi
done
if [[ -n "$NOJQ_LN_FAILED" ]]; then
  echo "SKIP: no-jq cases not asserted, native symlink failed for $NOJQ_LN_FAILED (Developer Mode off?); no coverage here, not a pass"
elif PATH="$NOJQ_PATH" type -P jq >/dev/null 2>&1; then
  bad "could not build a PATH without jq"
else
  run_nojq() {
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

  NOJQ_CMD=$(jq -c '. + {session_id: "nojq-s1"}' <<<"$(command_json 'cat > foo.txt && git commit -m x')")
  run_nojq "$NOJQ_CMD" block-convention-violation.sh block-noncanonical-commit.sh
  assert_exit "no jq, real guards: the advisory notices exit 0" 0 "$RC"
  assert_eq "no jq, real guards: exactly one JSON document on stdout" \
    "1" "$(grep -c '^{' <<<"$OUT")"
  assert_contains "no jq, real guards: one plugin-level notice is emitted" \
    "$OUT" "guardrails: jq not on the hook PATH"
  assert_absent "no jq, real guards: the second guard's notice is not produced" \
    "$ERR" "run-guards: dropped"
  run_nojq "$NOJQ_CMD" block-convention-violation.sh block-noncanonical-commit.sh
  assert_silent "no jq, real guards: a later call in the session stays quiet" "$OUT$ERR"
  run_nojq "$(jq -c '.session_id = "nojq-s2"' <<<"$NOJQ_CMD")" block-convention-violation.sh block-no-verify.sh
  assert_exit "no jq, real guards: a fail-closed guard still wins the exit code" 2 "$RC"
  assert_contains "no jq, real guards: the fail-closed reason reaches stderr" \
    "$ERR" "BLOCKED: jq is not on PATH, so guardrails denies every Bash and PowerShell call, and every file write on Windows."
  assert_absent "no jq, real guards: a block's deny reason carries no dropped document" \
    "$ERR" "run-guards: dropped"
fi

run "$PAYLOAD" "$TEST_TMPDIR/nope.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "missing guard surfaces as rc 1" 1 "$RC"
assert_contains "missing guard is named" "$ERR" "guard not found"
assert_eq "the other guard still ran" $'git status --short\nBash' "$(cat "$SEEN")"

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

hard_stub() {
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

# A guard's `exit` once ran the next guard from inside its own call, so a guard
# that exited deep left its frames under every guard after it. Git Bash has a
# 2 MB stack: an attended alias walk that exited about 140 frames down, then a
# second walk, overflowed it, and bash died with exit 0 and no output, an
# allow. Now `exit` unwinds the guard, and after a deep exit the rest runs in a
# forked process; its documents and status still count. The depth a later
# guard sees is the structural pin; it holds on every platform.
deep_stub() { # <name> <status>: recurse 100 frames, then exit <status> from the bottom
  stub "$1" 'd() { if (($1)); then d $(($1 - 1)); else exit '"$2"'; fi; }
d 100'
}
deep_stub deep0.sh 0
deep_stub deep2.sh 2
stub depth.sh 'echo "depth=${#FUNCNAME[@]}" >>"'"$SEEN"'"; exit 0'
stub die.sh 'echo die >>"'"$SEEN"'"; kill -9 "$BASHPID"'
run "$PAYLOAD" "$TEST_TMPDIR/deep0.sh" "$TEST_TMPDIR/depth.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "deep exit: the rest of the chain still runs" 0 "$RC"
deep_seen=$(cat "$SEEN")
assert_eq "deep exit: the next guard starts on a fresh stack" "depth=5" "${deep_seen%%$'\n'*}"
assert_eq "deep exit: each later guard ran once" $'depth=5\ngit status --short\nBash' "$deep_seen"
stub depth1.sh 'echo "depth=${#FUNCNAME[@]}" >>"'"$SEEN"'"; exit 0'
run "$PAYLOAD" "$TEST_TMPDIR/deep0.sh" "$TEST_TMPDIR/depth1.sh"
assert_eq "deep exit: the guard's frames are gone, not under the next guard" "depth=5" "$(cat "$SEEN")"
stub shallow0.sh 'exit 0'
run "$PAYLOAD" "$TEST_TMPDIR/shallow0.sh" "$TEST_TMPDIR/depth1.sh"
assert_eq "shallow exit: the next guard runs on the dispatcher's own stack" "depth=3" "$(cat "$SEEN")"
run "$PAYLOAD" "$TEST_TMPDIR/deep2.sh" "$TEST_TMPDIR/ask1.sh" "$TEST_TMPDIR/ctx1.sh"
assert_exit "deep exit 2: the block wins over the forked rest's documents" 2 "$RC"
assert_absent "deep exit 2: the ask from the forked rest is dropped" "$OUT" '"ask"'
assert_contains "deep exit 2: the forked rest's context is kept" "$(hsd additionalContext)" "ctx one"
stub harddeep.sh 'source "'"$HOOK_DIR"'/abort-boundary.sh"
guard::abort_boundary harddeep PreToolUse open 0 2
d() { if (($1)); then d $(($1 - 1)); else : "${RUN_GUARDS_TEST_UNBOUND?forced abort}"; fi; }
d 100'
run "$PAYLOAD" "$TEST_TMPDIR/harddeep.sh" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/block.sh"
assert_exit "deep hard error: the fresh dispatcher's block comes back" 2 "$RC"
run "$PAYLOAD" "$TEST_TMPDIR/harddeep.sh" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "deep hard error: the fresh dispatcher's status comes back" 0 "$RC"
assert_contains "deep hard error: the fresh dispatcher's documents come back" "$(hsd additionalContext)" "ctx one"
stub restdeep.sh 'RUN_GUARDS_MAX_DEPTH=0
run_guards::run_rest $((RUN_GUARDS_CUR + 1))
run_guards::finish'
run "not json" "$TEST_TMPDIR/restdeep.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "deep hard error, unprimed payload: denied" 2 "$RC"
assert_contains "deep hard error, unprimed payload: the reason names it" "$ERR" "reported no verdict"
run "$PAYLOAD" "$TEST_TMPDIR/deep0.sh" "$TEST_TMPDIR/die.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "deep exit, then the rest dies unreported: denied" 2 "$RC"
assert_contains "deep exit, then the rest dies unreported: the reason names it" "$ERR" "reported no verdict"
run "$PAYLOAD" "$TEST_TMPDIR/hard.sh" "$TEST_TMPDIR/die.sh" "$TEST_TMPDIR/allow.sh"
assert_exit "hard error, then the rest dies unreported: denied" 2 "$RC"
stub mergeabort.sh 'hook::emit_document "{\"systemMessage\":\"b\"}"
jq() { return 1; }
run_guards::emit_one() { : "${RG_PROBE_UNBOUND?probe abort}"; }
exit 0'
run "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/mergeabort.sh"
assert_exit "a block, then the merge aborts: still denied" 2 "$RC"
assert_contains "a block, then the merge aborts: the fail-closed line is on stderr" "$ERR" "fail-closed"
run "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/mergeabort.sh"
assert_exit "no block, then the merge aborts: the open posture allows" 0 "$RC"

VERDICT="$TEST_TMPDIR/verdict"
verdict_seen() { if [[ -e "$VERDICT" ]]; then echo yes; else echo no; fi; }
verdict_run() {
  local label="$1" want="$2" input="$3" g
  shift 3
  local -a opts=(--hook "$1")
  shift
  for g in "$@"; do opts+=(--also "$g"); done
  rm -f "$VERDICT"
  guard_invoke --via dispatched --payload "$input" "${opts[@]}" -- "EXEC_BASH_VERDICT_FILE=$VERDICT"
  assert_eq "verdict marker: $label" "$want" "$(verdict_seen)"
}
verdict_run "an allow writes it" yes "$PAYLOAD" "$TEST_TMPDIR/allow.sh"
verdict_run "a block writes it" yes "$PAYLOAD" "$TEST_TMPDIR/block.sh"
verdict_run "empty stdin writes it" yes "" "$TEST_TMPDIR/allow.sh"
verdict_run "cut-short stdin writes it" yes "$CUT_PREFIX" "$TEST_TMPDIR/allow.sh"
verdict_run "a guard's hard error the chain finishes writes it" yes "$PAYLOAD" "$TEST_TMPDIR/hard.sh" "$TEST_TMPDIR/allow.sh"
verdict_run "a deep exit whose rest forks writes it" yes "$PAYLOAD" "$TEST_TMPDIR/deep0.sh" "$TEST_TMPDIR/allow.sh"
verdict_run "a dispatcher killed mid-chain writes none" no "$PAYLOAD" "$TEST_TMPDIR/die.sh" "$TEST_TMPDIR/allow.sh"
verdict_run "an abort in the dispatcher's own merge writes none" no "$PAYLOAD" "$TEST_TMPDIR/ctx1.sh" "$TEST_TMPDIR/mergeabort.sh"
assert_exit "verdict marker: with one expected, the dispatcher's own abort denies" 2 "$GUARD_RC"
assert_contains "verdict marker: the abort line says the call is denied" "$GUARD_ERR" "fail-closed"
rm -f "$VERDICT"
EXEC_BASH_VERDICT_FILE="$VERDICT" bash "$DISPATCH" --report "" "$TEST_TMPDIR/allow.sh" <<<"$PAYLOAD" >/dev/null 2>&1
assert_eq "verdict marker: a --report process writes none" no "$(verdict_seen)"
rm -f "$VERDICT"
EXEC_BASH_VERDICT_FILE="$VERDICT" bash "$DISPATCH" --max-substitutions 1 "$TEST_TMPDIR/allow.sh" \
  <<<"$(jq -n '{tool_name:"Bash",tool_input:{command:"echo $(a) $(b)"}}')" >/dev/null 2>&1
assert_exit "verdict marker: the substitution cap still blocks" 2 "$?"
assert_eq "verdict marker: the substitution cap writes it" yes "$(verdict_seen)"

ALIAS_CMD='git -c "alias.sh=!git --config-env=alias.c=AV c --allow-empty -m x" sh'
alias_alone_rc=0
alias_alone_err=$(bash "$HOOK_DIR/block-noncanonical-commit.sh" <<<"$(command_json "$ALIAS_CMD")" 2>&1 >/dev/null) || alias_alone_rc=$?
assert_exit "alias chain: block-noncanonical-commit alone denies" 2 "$alias_alone_rc"
guard_invoke --via dispatched --payload "$(command_json "$ALIAS_CMD")" \
  --hook block-dangerous-git.sh --also block-noncanonical-commit.sh -- RUN_GUARDS_PROFILE=1
assert_exit "alias chain: dispatched pair denies" 2 "$GUARD_RC"
assert_contains "alias chain: the first guard refuses" "$GUARD_ERR" "rc=2 block-dangerous-git.sh"
assert_contains "alias chain: the second guard refuses too (its memo was reset)" \
  "$GUARD_ERR" "rc=2 block-noncanonical-commit.sh"
assert_eq "alias chain: the shared refusal is printed once" 1 \
  "$(grep -c "$(head -1 <<<"$alias_alone_err")" <<<"$GUARD_ERR")"

DUAL_PS=$(pwsh_command_json 'Invoke-Command -ScriptBlock { git reset --hard }')
guard_invoke --via dispatched --payload "$DUAL_PS" --lib lib/powershell/ps-command.sh \
  --hook block-no-verify.sh --also block-dangerous-git.sh -- RUN_GUARDS_PROFILE=1
assert_exit "PS dual sink: dispatched pair denies" 2 "$GUARD_RC"
assert_contains "PS dual sink: block-no-verify denies" "$GUARD_ERR" "rc=2 block-no-verify.sh"
assert_contains "PS dual sink: block-dangerous-git denies too" "$GUARD_ERR" "rc=2 block-dangerous-git.sh"
assert_eq "PS dual sink: the sink message is printed once" 1 \
  "$(grep -c 'cannot be parsed with confidence' <<<"$GUARD_ERR")"
assert_contains "PS dual sink: the one message names the token both guards honor" \
  "$GUARD_ERR" "the user adds ps-unparsable-special-construct to block_dangerous_git_allow; it clears block-dangerous-git too"
assert_absent "PS dual sink: no kill switch in the deny reason" "$GUARD_ERR" "_enabled"

SINK_ERR=$(bash -c '
  . "$1/../lib/powershell/ps-command.sh"
  PS_SINK_TRIGGER=special-construct
  ps::print_unparsable_block_message x
  ps::print_unparsable_git_block_message
  PS_SINK_TRIGGER=launcher
  ps::print_unparsable_git_block_message
  ps::print_sink_budget_message
  ps::print_sink_budget_message
' _ "$HOOK_DIR" 2>&1)
assert_eq "PS sink latch: the same trigger prints once" 1 \
  "$(grep -c 'ps-unparsable-special-construct' <<<"$SINK_ERR")"
assert_contains "PS sink latch: a second trigger still prints its token" \
  "$SINK_ERR" "the user adds ps-unparsable-launcher"
assert_eq "PS sink latch: the budget message prints once" 1 \
  "$(grep -c 'five allowed sink shapes' <<<"$SINK_ERR")"

NUL_PAYLOAD=$(jq -cn '{tool_name:"Bash",tool_input:{command:("git status" + ([0] | implode) + "x")}}')
guard_invoke --via dispatched --payload "$NUL_PAYLOAD" --hook block-no-verify.sh \
  --also block-dangerous-git.sh --also block-credential-read.sh --also block-root-delete-target.sh
assert_exit "NUL payload: the row denies" 2 "$GUARD_RC"
assert_eq "NUL payload: the refusal is printed once" 1 "$(grep -c 'NUL byte' <<<"$GUARD_ERR")"
guard_invoke --via dispatched --payload '{"tool_name":"Bash","tool_input":"x"}' --hook block-no-verify.sh \
  --also block-dangerous-git.sh --also block-credential-read.sh --also block-root-delete-target.sh
assert_exit "unparsable payload: the row denies" 2 "$GUARD_RC"
assert_eq "unparsable payload: one refusal line" 1 "$(grep -c 'BLOCKED' <<<"$GUARD_ERR")"

bypass=$(command_json 'git commit --no-verify -m x')
alone_rc=0
alone_err=$(bash "$HOOK_DIR/block-no-verify.sh" <<<"$bypass" 2>&1 >/dev/null) || alone_rc=$?
run "$bypass" --lib lib/powershell/ps-command.sh block-no-verify.sh block-dangerous-git.sh
assert_exit "real guard blocks through the dispatcher" 2 "$RC"
assert_eq "real guard: same exit alone and dispatched" "$alone_rc" "$RC"
assert_eq "real guard: same stderr alone and dispatched" "$alone_err" "$ERR"

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
  "$POST_CTX" "  docs/gone.md"
assert_contains "two real emitters: the unresolved skill is in the merged context" \
  "$POST_CTX" "  /alpha:nosuch"
assert_eq "two real emitters: merged hookEventName kept" \
  "PostToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$GUARD_OUT")"
if [[ "${POST_CTX%%$'\n'*}" == stale-path-verify* ]]; then
  ok "two real emitters: merged in dispatch order"
else
  bad "two real emitters: merged out of dispatch order: ${POST_CTX%%$'\n'*}"
fi

for one in stale-path-verify skill-reference-verify; do
  guard_invoke --payload "$POST_PAYLOAD" --hook "$HOOK_DIR/$one.sh" -- "${POST_ENV[@]}"
  assert_eq "$one alone: one document" "1" "$(jq -s 'length' <<<"$GUARD_OUT")"
  assert_contains "merged context contains what $one says alone" "$POST_CTX" \
    "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$GUARD_OUT" | tr -d '\r' | head -2 | tail -1)"
done

for g in secret-pattern-detection hardcoded-path-check block-no-verify block-dangerous-git \
  flag-commit-pr-skill-bypass block-noncanonical-commit \
  block-convention-violation block-windows-drive-tmp block-exported-msys-pathconv \
  block-root-delete-target block-fix-request-post block-github-post-content block-cross-domain block-cd-prefix block-foreground-wait block-lane-pr-disable-auto block-main-checkout-edit; do
  n=$(jq -r --arg g "$g.sh" '[.hooks[][] | .hooks[] | if (.args | type) == "array" then (.args | map(tostring) | join(" ")) else .command end | select(contains("run-guards.sh") and contains(" " + $g))] | length' "$HOOKS_JSON")
  if ((n > 0)); then ok "hooks.json dispatches $g"; else bad "hooks.json does not dispatch $g"; fi
  if [[ -f "$HOOK_DIR/$g.sh" ]]; then ok "$g.sh exists on disk"; else bad "$g.sh missing on disk"; fi
done

# --- the reference-verify git hook reads every extension the verifiers do -----
# The three verifiers run at commit time through git-hooks/reference-verify.sh,
# which hands over only the extensions its own `case "$f"` lists. That list must
# equal the union of the verifiers' `case "$FILE"` gates: an extension a gate
# accepts and the list omits is a verifier that silently never runs on it. Both
# sides are read from the scripts' source rather than a second hand-kept list.
gate_exts_of() { # $1 verifier name -> its case-gate extensions, one per line
  sed -n '/^case "\$FILE" in/,/^esac/p' "$HOOK_DIR/$1.sh" | grep -v '^[[:space:]]*#' | grep -oE '\*\.[a-z0-9]+' | sed 's/^\*\.//' | sort -u
}
git_hook_exts=$(sed -n '/^  case "\$f" in/,/^  esac/p' "$HOOK_DIR/../git-hooks/reference-verify.sh" |
  grep -oE '\*\.[a-z0-9]+' | sed 's/^\*\.//' | sort -u | tr '\n' ' ')
gate_exts=$(for v in cli-flag-verify skill-reference-verify stale-path-verify; do gate_exts_of "$v"; done | sort -u | tr '\n' ' ')
assert_eq "reference-verify.sh extensions equal the union of the verifiers' case gates" "$gate_exts" "$git_hook_exts"
assert_eq "no PostToolUse row is left for the verifiers" 0 \
  "$(jq '[.hooks.PostToolUse // [] | .[] | .hooks[]] | length' "$HOOKS_JSON")"

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

prime_filters() {
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
declared_fields() {
  local -a f=()
  read -r -a f <<<"${GUARD_FIELDS[$1]-}"
  ((${#f[@]})) && printf '%s\n' "${f[@]}" | sort -u
  return 0
}
declared_unprimed() {
  local d="${GUARD_FIELDS_UNPRIMED[$1]-}"
  [[ -n "$d" ]] && printf '%s\n' "$d" | sort -u
  return 0
}
declared_libs() {
  local -a l=()
  read -r -a l <<<"${GUARD_LIBS[$1]-}"
  ((${#l[@]})) && printf '%s\n' "${l[@]}" | sort -u
  return 0
}
guards_of() {
  local -a toks=()
  read -r -a toks <<<"$1"
  local i=0 tok
  while ((i < ${#toks[@]})); do
    tok="${toks[i]}"
    if [[ "$tok" == "--lib" || "$tok" == "--bps-seed" ]]; then
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
libs_of() {
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
lines_of() {
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

expect_both "declared library reaches block-dangerous-git either way" 2 \
  --hook "$HOOK_DIR/block-dangerous-git.sh" --tool PowerShell \
  --command 'git push --force origin main' \
  --lib lib/powershell/ps-command.sh
expect_both "declared library reaches block-no-verify either way" 2 \
  --hook "$HOOK_DIR/block-no-verify.sh" --tool PowerShell \
  --command 'git commit --no-verify -m x' \
  --lib lib/powershell/ps-command.sh
guard_invoke --via dispatched --hook "$HOOK_DIR/block-dangerous-git.sh" \
  --tool PowerShell --command 'git push --force origin main'
assert_exit "a dispatched row with no --lib still reaches the declared library" 2 "$GUARD_RC"

SPD_NONREPO="$TEST_TMPDIR/spd-nonrepo"
mkdir -p "$SPD_NONREPO"
SPD_TOKEN="AKIA""IOSFODNN7EXAMPLE"
guard_invoke --via dispatched --hook "$HOOK_DIR/secret-pattern-detection.sh" \
  --payload "$(write_json "$TEST_TMPDIR/spd-elsewhere/config.env" "config = '$SPD_TOKEN'")" \
  -- "CLAUDE_PROJECT_DIR=$SPD_NONREPO"
assert_exit "dispatched secret guard: non-repo root, outside write blocks" 2 "$GUARD_RC"
assert_contains "dispatched secret guard: names the pattern" "$GUARD_ERR" "AWS Access Key"

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

subst_cmd() {
  local s="echo " k
  for ((k = 0; k < $1; k++)); do s+='$(: rm)'; done
  printf '%s%s' "$s" "${2-}"
}
rep() {
  local s="" k
  for ((k = 0; k < $2; k++)); do s+="$1"; done
  printf '%s' "$s"
}
tool_payload() {
  jq -n --arg t "$1" --arg c "$2" '{tool_name:$t,cwd:"/x",tool_input:{command:$c}}'
}
cap_run() {
  local input="$1"
  shift
  : >"$SEEN"
  RC=0
  OUT=$(timeout 20 bash "$DISPATCH" "$@" <<<"$input" 2>"$TEST_TMPDIR/err") || RC=$?
  ERR=$(cat "$TEST_TMPDIR/err")
}
CAP_MSG="over the $ROW_CAP the guards can check in time"

cap_run "$(tool_payload Bash "$(subst_cmd "$ROW_CAP")")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: a command at the cap reaches the guards" 0 "$RC"
assert_contains "cap: the guard ran on a command at the cap" "$(cat "$SEEN")" 'echo $(: rm)'
cap_run "$(tool_payload Bash "$(subst_cmd "$((ROW_CAP + 1))")")" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: one past the cap is refused" 2 "$RC"
assert_contains "cap: the refusal names the cap" "$ERR" "$CAP_MSG"
assert_contains "cap: the refusal names the count" "$ERR" "BLOCKED: $((ROW_CAP + 1)) command or process substitutions"
assert_eq "cap: no guard is sourced past the cap" "" "$(cat "$SEEN")"
cap_run "$(tool_payload Bash "$(subst_cmd 2339)")" "$TEST_TMPDIR/allow.sh"
assert_exit "cap: without --max-substitutions nothing is counted" 0 "$RC"

OVER=$((ROW_CAP + 1))
QS=$(rep '$(:)' "$OVER")
NL=$'\n'
TAB=$'\t'
cap_quoted() {
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
cap_nul=$(jq -n --arg c "$(subst_cmd "$((ROW_CAP + 1))")" '{tool_name:"Bash",tool_input:{command:($c + ([0] | implode))}}')
cap_run "$cap_nul" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/nul.sh"
assert_exit "cap: an unprimed payload past the cap is refused" 2 "$RC"
cap_nul=$(jq -n '{tool_name:"Bash",tool_input:{command:("git " + ([0] | implode) + "x")}}')
cap_run "$cap_nul" --max-substitutions "$ROW_CAP" "$TEST_TMPDIR/nul.sh"
assert_eq "cap: an unprimed payload under the cap reaches the guard" "nul=1 cmd=git x" "$(cat "$SEEN")"
cap_run "$PAYLOAD" --max-substitutions 0 "$TEST_TMPDIR/block.sh"
assert_exit "cap: a malformed cap is the dispatcher's could-not-run, not a verdict" 0 "$RC"
assert_contains "cap: the malformed cap is reported" "$ERR" "rc=70"

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
cap_run "$(tool_payload Bash "echo '$(rep '$(: rm)' 2339)'")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: 2,339 single-quoted substitutions reach the guards" 0 "$RC"
cap_run "$(tool_payload Bash "echo '$(rep '$(: rm)' 2300)'; rm -rf /")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: a root delete after them is refused" 2 "$RC"
assert_contains "cap row: the root-delete guard refused it" "$ERR" "filesystem root"
assert_absent "cap row: the count did not" "$ERR" "$CAP_MSG"
cap_run "$(tool_payload Bash "cat <<'EOF'${NL}$(rep '$(: rm) ' 2000)${NL}EOF")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: 2,000 substitutions in a quoted heredoc body reach the guards" 0 "$RC"
cap_run "$(tool_payload Bash "bash <<'EOF'${NL}\$(rm -rf /)${NL}EOF")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: bash <<'EOF' with a root delete in a substitution is refused" 2 "$RC"
assert_contains "cap row: the root-delete guard refused it" "$ERR" "filesystem root"
cap_run "$(tool_payload Bash "bash <<'EOF'${NL}$(rep '$(: rm) ' 300)rm -rf /${NL}EOF")" "${BASH_ROW_ARGS[@]}"
assert_exit "cap row: bash <<'EOF' with 300 substitutions then a root delete is refused" 2 "$RC"
assert_contains "cap row: that one is refused by the count" "$ERR" "$CAP_MSG"
# bash runs each substitution in an unquoted heredoc body, so every guard on
# the row judges it as it judges the same text at top level; a quoted body is
# data (docs/contracts/hook-precision/README.md).
hd_row() { # <label> <expected rc> <command>
  cap_run "$(tool_payload Bash "$3")" "${BASH_ROW_ARGS[@]}"
  assert_exit "heredoc row: $1" "$2" "$RC"
}
hd_row "an unquoted body's \$(rm -rf /) is refused" 2 "cat <<EOF${NL}\$(rm -rf /)${NL}EOF"
assert_contains "heredoc row: the root-delete guard refused it" "$ERR" "filesystem root"
hd_row "a <<-EOF body's \$(rm -rf /) is refused" 2 "cat <<-EOF${NL}${TAB}\$(rm -rf /)${NL}${TAB}EOF"
hd_row "a \$[...] that runs a root delete in an unquoted body is refused" 2 "cat <<EOF${NL}\$[\$(rm -rf /)]${NL}EOF"
assert_contains "heredoc row: the root-delete guard refused the \$[...] one" "$ERR" "filesystem root"
hd_row "a \${...} that runs a root delete in an unquoted body is refused" 2 "cat <<EOF${NL}\${x:-\$(rm -rf /)}${NL}EOF"
assert_contains "heredoc row: the root-delete guard refused the \${...} one" "$ERR" "filesystem root"
hd_row "a body holding \$(date) is allowed" 0 "cat <<EOF${NL}today: \$(date)${NL}EOF"
hd_row "a body holding \$HOME is allowed" 0 "cat <<EOF${NL}home: \$HOME${NL}EOF"
hd_row "a quoted body holding \$(rm -rf /) is allowed" 0 "cat <<'EOF'${NL}\$(rm -rf /)${NL}EOF"
# No guard reads `${x@P}` or `$[1 + 2]`, so those rows hold whether or not the
# body is scanned; the rows whose top-level verdict is a refusal are the ones
# that can fail. `${ echo }; rm -rf /; }` pins the `${ ` command-substitution
# frame: a `${` frame that ended at the first `}` would let the delete through.
# shellcheck disable=SC2016  # literal shell text under test
for hd_expr in '${x@P}' '$[1 + 2]' '$[$(rm -rf /)]' '${x:-$(rm -rf /)}' '${ echo }; rm -rf /; }'; do
  cap_run "$(tool_payload Bash "$hd_expr")" "${BASH_ROW_ARGS[@]}"
  hd_top=$RC
  cap_run "$(tool_payload Bash "cat <<EOF${NL}$hd_expr${NL}EOF")" "${BASH_ROW_ARGS[@]}"
  assert_eq "heredoc row: $hd_expr in an unquoted body gets its top-level verdict" "$hd_top" "$RC"
done
BIG_CMD=$(printf '%*s' 20000 '' | tr ' ' x)
BIG_PAYLOAD=$(jq -nc --arg c "$BIG_CMD" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:$c}}')
AT_CMD=$(printf '%*s' 16384 '' | tr ' ' x)
AT_PAYLOAD=$(jq -nc --arg c "$AT_CMD" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:$c}}')
over_run() {
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
NUL_BIG_PAYLOAD=$(jq -nc --arg c "$BIG_CMD" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:($c + "\u0000")}}')
over_run "$NUL_BIG_PAYLOAD" --max-command-len 16384 "$TEST_TMPDIR/block.sh" "$TEST_TMPDIR/nul.sh"
assert_exit "unprimed over the ceiling: the block stands" 2 "$RC"
assert_eq "unprimed over the ceiling: no guard runs after the block" "0" "$(grep -c . "$SEEN")"
over_run "$PAYLOAD" --max-command-len 16k "$TEST_TMPDIR/allow.sh"
assert_eq "a --max-command-len that is not a whole number runs no guard" "" "$(cat "$SEEN")"
assert_contains "a --max-command-len that is not a whole number is reported" "$OUT$ERR" "run-guards"

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
HEREDOC_PAYLOAD=$(printf '%s' "cat > /tmp/out.txt <<'EOF'"$'\n'"${HEREDOC_BODY}EOF" |
  jq -Rsc '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:.}}')
[[ ${#HEREDOC_PAYLOAD} -gt 70000 ]] || bad "the ~70 KB payload was not built (${#HEREDOC_PAYLOAD} chars)"
row_t0=${EPOCHREALTIME:-}
ROW_ERR=$(cd "$HOOK_DIR" && RUN_GUARDS_PROFILE=1 bash "$DISPATCH" "${BASH_ROW_ARGS[@]}" <<<"$HEREDOC_PAYLOAD" 2>&1 >/dev/null)
ROW_RC=$?
row_t1=${EPOCHREALTIME:-}
assert_exit "the shipped row blocks a ~70 KB command" 2 "$ROW_RC"
assert_contains "the shipped row names the ceiling" "$ROW_ERR" "too long to check"
assert_eq "the shipped row runs one guard on a ~70 KB command" "1" "$(grep -c '^run-guards: .* ms rc=' <<<"$ROW_ERR")"
if [[ -n "$row_t0" && -n "$row_t1" ]]; then
  row_ms=$(((${row_t1/./} - ${row_t0/./}) / 1000))
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
printf "%s:HD [%s]\n" "$PARSE_LABEL" "${HOOK_HEREDOC_BODIES[*]-}" >>"'"$SEEN"'"
exit 0'
stub parse-a.sh "PARSE_LABEL=a; PARSE_EXIT_ON=; ${PARSE_BODY}"
stub parse-b.sh "PARSE_LABEL=b; PARSE_EXIT_ON=; ${PARSE_BODY}"
stub parse-c.sh "PARSE_LABEL=c; PARSE_EXIT_ON=; ${PARSE_BODY}"
stub parse-exit.sh "PARSE_LABEL=x; PARSE_EXIT_ON=echo; ${PARSE_BODY}"
SHARE_CMD=$'git commit -m "héllo ✓" 2>&1 >out.log && bash -c \'echo inner > f\'; cat <<EOF >>log\nbody\nEOF\necho "tail" <in'
SHARE_PAYLOAD=$(jq -nc --arg c "$SHARE_CMD" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:$c}}')
printf -v SHARE_WALK 'walk %q' "$SHARE_CMD"
share_by_label() {
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
assert_contains "shared parse: the heredoc body spans ride along" "$SHARE_ALONE" "HD [86 95 0 1 EOF]"
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
