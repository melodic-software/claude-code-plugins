#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

CLONES=0
EXECS=0
trace_counts() {
  local log="$WORK/trace.$$"
  strace -f -qq -o "$log" -e trace=clone,clone3,fork,vfork,execve \
    "$@" >/dev/null 2>/dev/null
  CLONES=$(grep -E '^[0-9]+ +(clone|clone3|fork|vfork)\(' "$log" 2>/dev/null | grep -vc CLONE_THREAD)
  EXECS=$(grep -cE '^[0-9]+ +execve\(' "$log" 2>/dev/null)
  EXECS=$((EXECS - 1))
  rm -f "$log"
}

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

REPO="$WORK/repo"
mkdir -p "$REPO/.github/workflows"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" remote add origin https://github.com/melodic-software/claude-code-plugins.git 2>/dev/null
printf 'jobs:\n  ci-status:\n    steps:\n      - uses: melodic-software/ci-workflows/.github/actions/pr-require-checks/check-contract@5e18f3d6cebd6fa5e66b0941ee0f7ed6ba288d6c # v0.58.0\n' \
  >"$REPO/.github/workflows/ci.yml"
mkdir -p "$REPO/docs/conventions"
printf "linkage_gate_uses_pattern: '%s'\n" '\.github/actions/pr-require-checks/(check-contract|report-ci-status)([@[:space:]]|$)' \
  >"$REPO/docs/conventions/source-control.yaml"

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
BAD_BODY='This does not close #1.'

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

export HOOK_TELEMETRY_SINK=""
export CLAUDE_PROJECT_DIR="$REPO"

run_hook() {
  local h="$1" p="$2" saved
  exec {saved}<&0
  trace_counts bash "$h" <"$p"
  exec 0<&"$saved" {saved}<&-
}

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

budget "bash gate / non-PR gh call" "$BASH_GATE" "$WORK/p-nonpr.json" 7 2
exact() {
  run_hook "$2" "$3"
  if ((CLONES == $4 && EXECS == $5)); then
    ok "$1: exactly $CLONES clone-family calls and $EXECS execve"
  else
    fail "$1: $CLONES clone-family calls and $EXECS execve, want exactly $4 and $5"
  fi
}
exact "bash gate / compliant body (ALLOW)" "$BASH_GATE" "$WORK/p-allow.json" 10 4
exact "bash gate / failing body (BLOCK)" "$BASH_GATE" "$WORK/p-block.json" 10 4
budget "mcp gate / unrelated tool" "$MCP_GATE" "$WORK/p-mcp-other.json" 7 2
budget "mcp gate / compliant body (ALLOW)" "$MCP_GATE" "$WORK/p-mcp-allow.json" 11 4
budget "mcp gate / failing body (BLOCK)" "$MCP_GATE" "$WORK/p-mcp-block.json" 11 4

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

MUT="$WORK/mut"
mkdir -p "$MUT"
cp "$HOOK_DIR"/hook-utils.sh "$HOOK_DIR"/pr-linkage-validator.sh "$HOOK_DIR"/pr-linkage-scope.sh "$MUT/"
mkdir -p "$WORK/lib"
cp "$HOOK_DIR"/../lib/yaml-subset.awk "$WORK/lib/"

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
