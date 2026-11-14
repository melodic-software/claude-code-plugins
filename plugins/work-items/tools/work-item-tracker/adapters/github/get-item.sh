#!/usr/bin/env bash
# get-item <id> [--history] — CONTRACT.md "Verbs (core public surface)". Read-only.
# --history adds state_history from the issue timeline's closed and reopened events: one
# paginated REST read, made only when asked for.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage="usage: get-item <id> [--history]"
wit_help_if_requested "$usage" "$@"

id="${1:-}"
history=0
if [[ $# -eq 2 && "$2" == "--history" ]]; then
  history=1
elif [[ $# -ne 1 ]]; then
  wit_usage_error "$usage"
fi
[[ -n "$id" ]] || wit_usage_error "$usage"
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id (expected github:<owner>/<repo>#<number>)"

if ((history == 0)); then
  wit_emit_item "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER"
  exit $?
fi

owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"
item="$(wit_emit_item "$owner" "$repo" "$number")" || exit $?
wit_run_gh read api --paginate "repos/$owner/$repo/issues/$number/timeline?per_page=100" \
  --jq '[.[] | select(.event == "closed" or .event == "reopened") | {state: .event, at: (.created_at // null), actor: (.actor.login // null)}]'
jq -c -s --argjson item "$item" 'add // [] | $item + {state_history: {available: true, events: .,
  reopen_count: (map(select(.state == "reopened")) | length), reason: null}}' <<<"$WIT_GH_OUT" || {
  echo "get-item: timeline response for $id is not JSON" >&2
  exit "$EX_INTERNAL"
}
