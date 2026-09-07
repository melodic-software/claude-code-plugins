#!/usr/bin/env bash
# Spawn budget for pr-body-linkage-gate.sh and pr-linkage-mcp-gate.sh (#3509).
#
# WHY A SEPARATE SUITE — the two gates' own contract suites
# (pr-body-linkage-gate.test.sh, pr-linkage-mcp-gate.test.sh) assert what the
# gates DECIDE. This one asserts what they COST, because on the host that filed
# #3509 process creation runs 0.3-0.9 s per spawn and every recorded run of
# `pr-body-linkage-gate.sh` exceeded its 15 s timeout — a gate that is killed
# before it renders a verdict protects nothing. The cost is therefore part of
# the contract, and `.claude/rules/hook-budget.md` states the ceiling it draws
# on (<= 1 s typical, <= 2 s worst case for a whole PreToolUse matcher).
#
# WHY strace AND NOT xtrace — an xtrace command-position count reads the SOURCE
# positions bash traced, not the processes the kernel created. `$(cmd 2>/dev/null)`
# is one xtrace line and two clones: bash execs in the command substitution's own
# subshell only when the command carries no redirection of its own, and a
# `2>/dev/null`, a `<<<`, or a pipeline inside the substitution defeats that and
# forks twice for one program. #3520 measured an xtrace count of 2 against 8 real
# kernel spawns on the same script. Only `strace -f -e trace=clone,clone3,fork,
# vfork,execve` sees the difference these hooks were changed to exploit, so only
# strace can fence it.
#
# WHAT IS FENCED — clone-family calls (the latency this issue is about) and
# execve (the work actually done). They move independently and both matter: a
# rewrite that trades one jq for three greps holds the clone count and blows the
# execve count, and a rewrite that reintroduces `$( … 2>/dev/null )` holds the
# execve count and blows the clone count.
#
# NON-VACUITY — a budget assertion passes trivially if the harness measures
# nothing, so this suite refuses to report a pass it has not earned:
#   1. a self-check runs two snippets whose kernel-level counts are known and
#      differ only by redirect placement; if the harness cannot tell them apart
#      it SKIPS rather than passing;
#   2. every budget is re-measured against a MUTATED copy of the hook that puts
#      one redirect back inside its command substitution, and the suite fails
#      unless the mutant's count actually rises.
#
# EXEMPT FROM THESE NUMBERS — spawns owned by lib/hook-utils.sh, which is a
# synced shared library this plugin does not change: `hook::buffer_stdin`'s
# payload validation (one jq) and `hook::repo_root` (one git). They are inside
# the totals because the totals are what the host pays, but a change to them
# belongs to that library's own budget, not this suite's.

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASH_GATE="$HOOK_DIR/pr-body-linkage-gate.sh"
MCP_GATE="$HOOK_DIR/pr-linkage-mcp-gate.sh"

PASS=0
FAIL=0
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

for tool in jq strace git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP: $tool not on PATH -- pr-linkage spawn-budget tests skipped"
    exit 0
  }
done

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# counts <label-out-vars> — run <cmd...> under strace and report kernel counts.
# CLONES and EXECS are set; the traced `bash` itself is subtracted from EXECS.
CLONES=0
EXECS=0
trace_counts() {
  local log="$WORK/trace.$$"
  strace -f -qq -o "$log" -e trace=clone,clone3,fork,vfork,execve \
    "$@" >/dev/null 2>/dev/null
  CLONES=$(grep -cE '^[0-9]+ +(clone|clone3|fork|vfork)\(' "$log" 2>/dev/null)
  EXECS=$(grep -cE '^[0-9]+ +execve\(' "$log" 2>/dev/null)
  EXECS=$((EXECS - 1))
  rm -f "$log"
}

# --- 0. Harness self-check ----------------------------------------------------
# Two snippets that run the SAME program and differ only in where the redirect
# sits. If the harness cannot see the extra fork the inner redirect causes, it
# cannot see the thing this suite exists to fence, so skip rather than pass.
printf 'x\n' >"$WORK/probe.txt"
trace_counts bash -c "V=\$(cat '$WORK/probe.txt' 2>/dev/null)"
INNER=$CLONES
trace_counts bash -c "{ V=\$(cat '$WORK/probe.txt'); } 2>/dev/null"
OUTER=$CLONES
if ((INNER > OUTER && OUTER >= 1)); then
  ok "harness: strace distinguishes redirect placement (inner=$INNER outer=$OUTER clones)"
else
  echo "SKIP: strace cannot observe fork elision here (inner=$INNER outer=$OUTER) -- budget unmeasurable"
  exit 0
fi

# --- Fixture ------------------------------------------------------------------
REPO="$WORK/repo"
mkdir -p "$REPO/.github/workflows"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" remote add origin https://github.com/melodic-software/claude-code-plugins.git 2>/dev/null
printf 'name: pr-issue-linkage\n' >"$REPO/.github/workflows/pr-issue-linkage.yml"

GOOD_BODY='Closes #1

## Summary
s

## Fix
f

## Verification
v

## Related
r
'
BAD_BODY='no linkage and no sections'

bash_payload() {
  jq -n --arg cwd "$REPO" --arg c "$1" \
    '{session_id:"budget",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}'
}
mcp_payload() {
  jq -n --arg cwd "$REPO" --arg t "$1" --arg b "$2" \
    '{session_id:"budget",cwd:$cwd,tool_name:$t,tool_input:{owner:"melodic-software",repo:"claude-code-plugins",title:"t",body:$b}}'
}

bash_payload 'gh issue view 3' >"$WORK/p-nonpr.json"
bash_payload "gh pr create --title t --body \"$GOOD_BODY\"" >"$WORK/p-allow.json"
bash_payload "gh pr create --title t --body \"$BAD_BODY\"" >"$WORK/p-block.json"
mcp_payload Read '' >"$WORK/p-mcp-other.json"
mcp_payload mcp__github__create_pull_request "$GOOD_BODY" >"$WORK/p-mcp-allow.json"
mcp_payload mcp__github__create_pull_request "$BAD_BODY" >"$WORK/p-mcp-block.json"

# A wired telemetry sink is the consuming repo's cost, not the gate's; pin it
# off so the budget measures the gate.
export HOOK_TELEMETRY_SINK=""
export CLAUDE_PROJECT_DIR="$REPO"

# run_hook <hook> <payload-file> — trace one hook invocation.
run_hook() {
  local h="$1" p="$2" saved
  exec {saved}<&0
  trace_counts bash "$h" <"$p"
  exec 0<&"$saved" {saved}<&-
}

# budget <label> <hook> <payload> <clone-ceiling> <exec-ceiling>
budget() {
  local label="$1" h="$2" p="$3" cmax="$4" emax="$5"
  run_hook "$h" "$p"
  if ((CLONES <= cmax)); then
    ok "$label: $CLONES clone-family calls (budget $cmax)"
  else
    fail "$label: $CLONES clone-family calls, budget is $cmax"
  fi
  if ((EXECS <= emax)); then
    ok "$label: $EXECS execve (budget $emax)"
  else
    fail "$label: $EXECS execve, budget is $emax"
  fi
}

# --- 1. Budgets ---------------------------------------------------------------
# Ceilings are the measured steady-state counts, with no headroom on purpose:
# every one of them is a spawn someone deliberately removed, and a silent
# re-addition is exactly what this suite is for. Raising a number here is a
# decision to be argued in the PR that raises it, per hook-budget.md rule 2
# ("the budget never relaxes to absorb an overage").
#
# The lib floor inside each number: one `jq -e .` from hook::buffer_stdin, plus
# one `git rev-parse` from hook::repo_root once a path reaches repo resolution.
budget "bash gate / non-PR gh call" "$BASH_GATE" "$WORK/p-nonpr.json" 7 2
budget "bash gate / compliant body (ALLOW)" "$BASH_GATE" "$WORK/p-allow.json" 11 3
budget "bash gate / failing body (BLOCK)" "$BASH_GATE" "$WORK/p-block.json" 11 3
budget "mcp gate / unrelated tool" "$MCP_GATE" "$WORK/p-mcp-other.json" 7 2
budget "mcp gate / compliant body (ALLOW)" "$MCP_GATE" "$WORK/p-mcp-allow.json" 11 4
budget "mcp gate / failing body (BLOCK)" "$MCP_GATE" "$WORK/p-mcp-block.json" 11 4

# The gates must still DECIDE, or a budget of zero spawns would pass. Cost and
# verdict are asserted on the same invocation set.
# verdict <label> <hook> <payload> <expected-rc>
verdict() {
  local label="$1" h="$2" p="$3" want="$4" rc=0
  bash "$h" <"$p" >/dev/null 2>&1 || rc=$?
  if ((rc == want)); then
    ok "$label (exit $rc)"
  else
    fail "$label: exit $rc, expected $want -- the budget above is measuring a no-op"
  fi
}
verdict "bash gate still DENIES the failing body" "$BASH_GATE" "$WORK/p-block.json" 2
verdict "bash gate still allows the compliant body" "$BASH_GATE" "$WORK/p-allow.json" 0
verdict "mcp gate still DENIES the failing body" "$MCP_GATE" "$WORK/p-mcp-block.json" 2
verdict "mcp gate still allows the compliant body" "$MCP_GATE" "$WORK/p-mcp-allow.json" 0

# --- 2. Mutation: the budgets must be able to FAIL ----------------------------
# Each mutant reverts exactly one of the changes #3509 made and must push the
# measured count back above the ceiling. A mutant that does not is a budget
# asserting nothing, and is reported as a failure of THIS suite.
MUT="$WORK/mut"
mkdir -p "$MUT"
cp "$HOOK_DIR"/hook-utils.sh "$HOOK_DIR"/pr-linkage-validator.sh "$MUT/"

# Mutant A — the redirect moved back INSIDE the command substitution. Same
# program, same output, one extra fork; this is the defect class #3779 named.
awk '
  /remote get-url origin/ {
    print "ORIGIN=$(git -C \"$REPO_ROOT\" remote get-url origin 2>/dev/null || true)"
    next
  }
  { print }
' "$MCP_GATE" >"$MUT/pr-linkage-mcp-gate.sh"
if grep -q 'remote get-url origin 2>/dev/null' "$MUT/pr-linkage-mcp-gate.sh"; then
  ok "mutant A built (redirect moved inside the substitution)"
  run_hook "$MUT/pr-linkage-mcp-gate.sh" "$WORK/p-mcp-allow.json"
  MUT_A=$CLONES
  run_hook "$MCP_GATE" "$WORK/p-mcp-allow.json"
  BASE_A=$CLONES
  if ((MUT_A > BASE_A)); then
    ok "mutant A raises clones $BASE_A -> $MUT_A (the clone budget is live)"
  else
    fail "mutant A did not raise the clone count ($BASE_A -> $MUT_A) -- clone budget is vacuous"
  fi
else
  fail "could not build mutant A -- the in-substitution redirect check is vacuous"
fi

# Mutant B — one batched field split back into its own `printf | jq` pipeline,
# the per-field shape #3509 replaced. Costs extra clones AND an extra execve.
awk '
  /^T_OWNER="\$\{HOOK_JQ_FIELDS\[2\]\}"$/ {
    print "T_OWNER=$(printf %s \"$INPUT\" | jq -r \".tool_input.owner // empty\" 2>/dev/null)"
    next
  }
  { print }
' "$MCP_GATE" >"$MUT/mcp-b.sh"
if grep -q 'jq -r ".tool_input.owner' "$MUT/mcp-b.sh"; then
  ok "mutant B built (one field split back out of the batch)"
  run_hook "$MUT/mcp-b.sh" "$WORK/p-mcp-allow.json"
  MUT_B_C=$CLONES
  MUT_B_E=$EXECS
  run_hook "$MCP_GATE" "$WORK/p-mcp-allow.json"
  if ((MUT_B_C > CLONES && MUT_B_E > EXECS)); then
    ok "mutant B raises clones $CLONES -> $MUT_B_C and execve $EXECS -> $MUT_B_E (both budgets live)"
  else
    fail "mutant B did not raise both counts (clones $CLONES -> $MUT_B_C, execve $EXECS -> $MUT_B_E)"
  fi
else
  fail "could not build mutant B -- the batching check is vacuous"
fi

# Mutant C — the validator's out-variable helpers reverted to stdout, which is
# the 12-fork shape. Exercised through the Bash gate, whose validated path is
# where those forks were paid.
cp "$BASH_GATE" "$MUT/pr-body-linkage-gate.sh"
awk '
  /^  linkage::chomp_to "\$__plv_dest" "\$out"$/ { print "  printf %s \"$out\"; printf -v \"$__plv_dest\" %s \"$(printf %s \"$out\")\""; next }
  { print }
' "$HOOK_DIR/pr-linkage-validator.sh" >"$MUT/pr-linkage-validator.sh"
# shellcheck disable=SC2016  # the literal source text of the mutant, not an expansion
if grep -q 'printf -v "\$__plv_dest" %s "\$(printf' "$MUT/pr-linkage-validator.sh"; then
  ok "mutant C built (a helper re-forks a command substitution)"
  run_hook "$MUT/pr-body-linkage-gate.sh" "$WORK/p-allow.json"
  MUT_C=$CLONES
  run_hook "$BASH_GATE" "$WORK/p-allow.json"
  if ((MUT_C > CLONES)); then
    ok "mutant C raises clones $CLONES -> $MUT_C (the validator's fork budget is live)"
  else
    fail "mutant C did not raise the clone count ($CLONES -> $MUT_C)"
  fi
else
  fail "could not build mutant C -- the validator fork check is vacuous"
fi

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0))
