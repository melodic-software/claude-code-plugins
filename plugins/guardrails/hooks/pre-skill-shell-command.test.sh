#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/hooks.json plugins/guardrails/hooks/*.sh
# test-scope: plugins/guardrails/hooks/*.mjs plugins/guardrails/lib/powershell/*
set -uo pipefail
export CLAUDE_CODE_SESSION_ATTENDED=0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$HOOK_DIR/.." && pwd)"
HOOKS_JSON="$HOOK_DIR/hooks.json"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free

for tool in jq node; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "FAIL: $tool is required for these tests" >&2
    exit 1
  }
done

PRE_ROW=$(jq -c '[.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell")]' "$HOOKS_JSON")
SKILL_ROW=$(jq -c '.hooks.PreSkillShellCommand // []' "$HOOKS_JSON")
assert_eq "hooks.json has one PreSkillShellCommand entry" 1 "$(jq length <<<"$SKILL_ROW")"
assert_eq "the entry matches both tools that run injected commands" "Bash|PowerShell" \
  "$(jq -r '.[0].matcher' <<<"$SKILL_ROW")"
assert_eq "the entry runs one hook" 1 "$(jq '.[0].hooks | length' <<<"$SKILL_ROW")"
for key in type command args timeout onFailure; do
  assert_eq "the hook's $key is the PreToolUse Bash|PowerShell hook's" \
    "$(jq -c ".[0].hooks[0].$key" <<<"$PRE_ROW")" "$(jq -c ".[0].hooks[0].$key" <<<"$SKILL_ROW")"
done
assert_eq "a failed or timed-out hook blocks the command" '"block"' \
  "$(jq -c '.[0].hooks[0].onFailure' <<<"$SKILL_ROW")"
assert_eq "the hook is not async, so it can block" false \
  "$(jq '.[0].hooks[0] | (.async // false) or (.asyncRewake // false)' <<<"$SKILL_ROW")"

ARGS=()
while IFS= read -r arg; do
  # shellcheck disable=SC2016  # the literal hooks.json placeholder
  ARGS+=("${arg//'${CLAUDE_PLUGIN_ROOT}'/$PLUGIN_DIR}")
done < <(jq -r '.[0].hooks[0].args[]' <<<"$SKILL_ROW")

WORK="$TEST_TMPDIR/work"
mkdir -p "$WORK"

run_row() {
  local event="$1" tool="$2" command="$3" payload
  if [[ "$event" == PreSkillShellCommand ]]; then
    payload=$(jq -nc --arg t "$tool" --arg c "$command" --arg d "$WORK" \
      --arg n "${4:-some-plugin:deploy}" --arg s "${5:-plugin}" --arg i "${6:-user}" \
      '{session_id:"s",transcript_path:"/dev/null",cwd:$d,permission_mode:"default",
        hook_event_name:"PreSkillShellCommand",tool_name:$t,tool_input:{command:$c},
        tool_use_id:"skill-cmd-1",command_name:$n,command_source:$s,invoked_by:$i}')
  else
    payload=$(jq -nc --arg t "$tool" --arg c "$command" --arg d "$WORK" \
      '{session_id:"s",transcript_path:"/dev/null",cwd:$d,permission_mode:"default",
        hook_event_name:"PreToolUse",tool_name:$t,tool_input:{command:$c},tool_use_id:"toolu_1"}')
  fi
  ROW_RC=0
  (
    cd "$WORK" || exit 99
    export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" CLAUDE_PROJECT_DIR="$WORK" \
      GIT_CEILING_DIRECTORIES="${TEST_TMPDIR%/*}"
    node "${ARGS[@]}" <<<"$payload"
  ) >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err" || ROW_RC=$?
  ROW_ERR=$(cat "$TEST_TMPDIR/err")
  ROW_OUT=$(cat "$TEST_TMPDIR/out")
  ROW_DECISION=$(jq -rs 'map(.hookSpecificOutput.permissionDecision // empty) | join(",")' \
    "$TEST_TMPDIR/out" 2>/dev/null)
}

parity() {
  local label="$1" want="$2" tool="$3" command="$4" pre_err pre_out pre_decision
  run_row PreToolUse "$tool" "$command"
  assert_exit "PreToolUse: $label" "$want" "$ROW_RC"
  pre_err=$ROW_ERR pre_out=$ROW_OUT pre_decision=$ROW_DECISION
  run_row PreSkillShellCommand "$tool" "$command"
  assert_exit "PreSkillShellCommand: $label" "$want" "$ROW_RC"
  assert_eq "PreSkillShellCommand: $label, same reason on stderr" "$pre_err" "$ROW_ERR"
  assert_eq "PreSkillShellCommand: $label, same reply on stdout" "$pre_out" "$ROW_OUT"
  assert_eq "PreSkillShellCommand: $label, same decision" "$pre_decision" "$ROW_DECISION"
}

parity "git commit --no-verify is refused" 2 Bash "git commit --no-verify -m x"
assert_contains "the --no-verify refusal says BLOCKED" "$ROW_ERR" "BLOCKED"
parity "git push --force to main is refused" 2 Bash "git push --force origin main"
parity "PowerShell git commit --no-verify is refused" 2 PowerShell "git commit --no-verify -m x"

parity "git status --short is allowed" 0 Bash "git status --short"
assert_eq "the allowed command gets no deny or ask" "" "$ROW_DECISION"
parity "git log --oneline -5 is allowed" 0 Bash "git log --oneline -5"
parity "PowerShell Get-ChildItem is allowed" 0 PowerShell "Get-ChildItem"

run_row PreSkillShellCommand Bash "git commit --no-verify -m x" guardrails:audit builtin claude
assert_exit "a refusal holds whatever skill, source and invoker the payload names" 2 "$ROW_RC"
run_row PreSkillShellCommand Bash "git status --short" source-control:commit projectSettings other
assert_exit "an allow holds whatever skill, source and invoker the payload names" 0 "$ROW_RC"

# An ask blocks an injected command the same as a deny:
# https://code.claude.com/docs/en/hooks#preskillshellcommand-decision-control
export CLAUDE_CODE_SESSION_ATTENDED=1
run_row PreSkillShellCommand Bash "git reset --hard"
assert_exit "attended: git reset --hard exits 0 with its ask" 0 "$ROW_RC"
assert_eq "attended: the decision is ask, which blocks an injected command" ask "$ROW_DECISION"
assert_eq "attended: the reply names hookEventName PreToolUse" PreToolUse \
  "$(jq -rs 'map(.hookSpecificOutput.hookEventName // empty) | join(",")' <<<"$ROW_OUT")"
export CLAUDE_CODE_SESSION_ATTENDED=0

event_identity_reads() {
  grep -nE 'hook_event_name|command_name|command_source|invoked_by' "$@" || true
}
# shellcheck disable=SC2016  # fixture text, not expanded here
printf 'ev=$(jq -r .hook_event_name)\n' >"$TEST_TMPDIR/reads-event.sh"
# shellcheck disable=SC2016  # fixture text, not expanded here
printf 'src=$(jq -r .command_source)\n' >"$TEST_TMPDIR/reads-source.sh"
assert_contains "a read of .hook_event_name is detected" \
  "$(event_identity_reads "$TEST_TMPDIR/reads-event.sh")" "hook_event_name"
assert_contains "a read of .command_source is detected" \
  "$(event_identity_reads "$TEST_TMPDIR/reads-source.sh")" "command_source"
loaded=()
for f in "$HOOK_DIR"/*.sh "$HOOK_DIR"/*.mjs "$PLUGIN_DIR"/lib/powershell/*; do
  [[ "$f" == *.test.* || "$f" == */guardrails-test-helpers.sh ]] && continue
  loaded+=("$f")
done
assert_silent "no hook script or library reads the event or skill identity fields" \
  "$(event_identity_reads "${loaded[@]}")"

report
