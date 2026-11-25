#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_PR_POLLER_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-pr-poller PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70

hook::buffer_stdin_to INPUT || exit 0

[[ "$INPUT" == *sleep* && "$INPUT" == *gh* ]] || exit 0

hook::require jq "PreToolUse" guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || exit 0
((HOOK_JQ_FIELDS_NUL)) && exit 0

PRP_COMMAND="${HOOK_JQ_FIELDS[0]}"
PRP_TOOL="${HOOK_JQ_FIELDS[1]:-}"
[[ "$PRP_TOOL" == Monitor || "$PRP_TOOL" == Bash ]] || exit 0
[[ -n "$PRP_COMMAND" ]] || exit 0
[[ "$PRP_COMMAND" == *monitor-poll.sh* ]] && exit 0

PRP_NL=$'\n'
PRP_B='(^|[^[:alnum:]_.-])'
PRP_E='([^[:alnum:]_-]|$)'
PRP_SLEEP_RE="${PRP_B}sleep[[:space:]]"
PRP_PR_RE="${PRP_B}gh[[:space:]]+pr[[:space:]]+(view|checks|status)${PRP_E}"
PRP_API_RE="${PRP_B}gh[[:space:]]+api${PRP_E}"
PRP_PATH_RE="/pulls${PRP_E}|/actions/artifacts|/check-runs|/commits/[^/[:space:]]+/status|/issues/[^/[:space:]]+/comments"
PRP_WHILE_RE="${PRP_B}(while|until)[[:space:]]"
PRP_CFOR_RE="${PRP_B}for[[:space:]]*\(\("
PRP_FOR_RE="${PRP_B}for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+([^;${PRP_NL}]*)"
PRP_RANGE_RE='\{[^}]*\.\.[^}]*\}'

[[ "$PRP_COMMAND" =~ $PRP_SLEEP_RE ]] || exit 0
[[ "$PRP_COMMAND" =~ $PRP_PR_RE ]] ||
  { [[ "$PRP_COMMAND" =~ $PRP_API_RE ]] && [[ "$PRP_COMMAND" =~ $PRP_PATH_RE ]]; } || exit 0

PRP_LOOP=0
if [[ "$PRP_COMMAND" =~ $PRP_WHILE_RE || "$PRP_COMMAND" =~ $PRP_CFOR_RE ]]; then
  PRP_LOOP=1
else
  PRP_REST="$PRP_COMMAND"
  while [[ "$PRP_REST" =~ $PRP_FOR_RE ]]; do
    PRP_LIST="${BASH_REMATCH[2]}"
    if [[ "$PRP_LIST" == *'$'* || "$PRP_LIST" == *'`'* || "$PRP_LIST" =~ $PRP_RANGE_RE ]]; then
      PRP_LOOP=1
      break
    fi
    PRP_REST="${PRP_REST#*"${BASH_REMATCH[0]}"}"
  done
fi
((PRP_LOOP)) || exit 0

if [[ "$PRP_TOOL" == Bash ]]; then
  hook::jq_fields "$INPUT" '.tool_input.run_in_background' || exit 0
  [[ "${HOOK_JQ_FIELDS[0]-}" == true ]] || exit 0
fi

# shellcheck disable=SC2016  # the backticks are literal text in the reason
echo 'BLOCKED: This loop polls a pull request and sleeps between reads, which spends the GitHub API budget. Watch a pull request with /source-control:pull-request monitor (it reports checks, review threads and the pr-verify verdict); for one change event, use `gh event listen --resource <pr url>`.' >&2
exit 2
