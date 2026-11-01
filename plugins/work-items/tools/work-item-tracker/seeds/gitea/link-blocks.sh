#!/usr/bin/env bash
# link-blocks — Gitea / Forgejo adapter (provider `gitea`).
# Scaffolded by /work-items:onboard-adapter; the provider mapping below is written
# against POST /repos/{owner}/{repo}/issues/{index}/dependencies, documented as "make
# the issue in the url depend on the issue in the form" — i.e. the URL issue becomes
# BLOCKED BY the body issue, which is the direction this verb wants. The sibling
# /blocks endpoint is the same edge read from the other end and would invert it.
#
# Contract: tools/work-item-tracker/CONTRACT.md — "Verbs", "Adapter contract",
# "JSON output contract", "Exit codes".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: link-blocks.sh <id> --blocked-by <id>'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
BLOCKED_BY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --blocked-by)
    [[ $# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
    BLOCKED_BY="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
wit_require_gitea_id "$ID" || wit_usage_error "not a gitea item id: $ID"
TARGET_OWNER="$WIT_ID_OWNER"
TARGET_REPO="$WIT_ID_REPO"
TARGET_NUMBER="$WIT_ID_NUMBER"
[[ -n "$BLOCKED_BY" ]] || wit_usage_error "--blocked-by is required"
wit_require_gitea_id "$BLOCKED_BY" || wit_usage_error "not a gitea item id: $BLOCKED_BY"
BLOCKER_OWNER="$WIT_ID_OWNER"
BLOCKER_REPO="$WIT_ID_REPO"
BLOCKER_NUMBER="$WIT_ID_NUMBER"

# An item cannot block itself; Gitea rejects the self-edge, but catching it here keeps
# the diagnostic about the request rather than about the provider's error text.
[[ "$ID" != "$BLOCKED_BY" ]] || wit_usage_error "an item cannot be blocked by itself: $ID"

wit_need_gitea_config

# BOTH ends are checked against the declared scope. Gitea supports cross-repository
# dependency edges (IssueMeta carries owner and repo), so the blocker can legitimately
# live in a different repository — but not in one this binding never declared.
wit_gitea_scope_in_scope "$TARGET_OWNER/$TARGET_REPO" ||
  wit_usage_error "$TARGET_OWNER/$TARGET_REPO is not in config.gitea.scopes"
wit_gitea_scope_in_scope "$BLOCKER_OWNER/$BLOCKER_REPO" ||
  wit_usage_error "blocker repo $BLOCKER_OWNER/$BLOCKER_REPO is not in config.gitea.scopes"

wit_gitea_http POST "/repos/$TARGET_OWNER/$TARGET_REPO/issues/$TARGET_NUMBER/dependencies" \
  "$(jq -cn --arg o "$BLOCKER_OWNER" --arg r "$BLOCKER_REPO" --argjson i "$BLOCKER_NUMBER" \
    '{owner: $o, repo: $r, index: $i}')"
wit_gitea_require_ok "linking $ID as blocked by $BLOCKED_BY"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$ID" --arg by "$BLOCKED_BY" \
  '{schema_version: $sv, id: $id, blocked_by: $by, linked: true}'
