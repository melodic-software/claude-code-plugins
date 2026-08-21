#!/usr/bin/env bash
# list-items — Gitea / Forgejo adapter (provider `gitea`).
# Scaffolded by /work-items:onboard-adapter; the provider mapping below is written
# against GET /repos/{owner}/{repo}/issues and the Gitea `Issue` struct.
#
# Contract: tools/work-item-tracker/CONTRACT.md — "Verbs", "Adapter contract",
# "JSON output contract", "Exit codes".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: list-items.sh [--state open|closed|all] [--repo <o>/<r>]'
wit_help_if_requested "$USAGE" "$@"

STATE="open"
REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --state)
    [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
    STATE="$2"
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 ]] || wit_usage_error "--repo needs a value"
    REPO="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
case "$STATE" in
open | closed | all) ;;
*) wit_usage_error "--state must be one of: open, closed, all" ;;
esac

wit_need_gitea_config

# With no --repo, the single declared scope is the target. Two or more declared scopes
# make the target ambiguous, and picking the first would quietly list the wrong
# repository — so it is a usage error naming the fix, not a guess.
if [[ -z "$REPO" ]]; then
  if [[ "$(jq 'length' <<<"$WIT_GITEA_SCOPES")" != "1" ]]; then
    wit_usage_error "--repo is required when config.gitea.scopes declares more than one repository"
  fi
  REPO="$(jq -r '.[0]' <<<"$WIT_GITEA_SCOPES")"
fi
# --repo is caller-supplied text that reaches a request path, so it is matched against
# the same anchored allowlist the binding's own scopes were, then against the declared
# scope list (the authorization boundary).
[[ "$REPO" =~ $WIT_GITEA_SCOPE_RE ]] ||
  wit_usage_error "--repo must be <owner>/<repo>: $REPO"
wit_gitea_scope_in_scope "$REPO" ||
  wit_usage_error "$REPO is not in config.gitea.scopes (the declared read scope)"
wit_gitea_scope_parts "$REPO"

# Gitea's `state` query parameter takes open|closed|all — the seam's own vocabulary, so
# it passes through. STATE is already constrained to those three by the parse above.
PAGE=1
COLLECTED='[]'
while :; do
  wit_gitea_http GET "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/issues?state=$STATE&page=$PAGE&limit=$WIT_GITEA_PAGE_SIZE"
  wit_gitea_require_ok "listing issues in $REPO"
  GOT="$(jq 'length' <<<"$WIT_GITEA_BODY" 2>/dev/null)" || {
    printf 'list-items.sh: gitea returned a non-array issue list for %s\n' "$REPO" >&2
    exit "$EX_INTERNAL"
  }
  # Gitea's issue list includes PULL REQUESTS: a PR is an issue with `pull_request`
  # populated. The seam's items are issues, and a PR arriving as a work item would be
  # claimed and worked like one, so they are dropped here rather than downstream.
  COLLECTED="$(jq -c --argjson acc "$COLLECTED" \
    '$acc + [ .[] | select(.pull_request == null) ]' <<<"$WIT_GITEA_BODY")"
  # A short page is the last page: Gitea sends no total-count header on this endpoint.
  ((GOT < WIT_GITEA_PAGE_SIZE)) && break
  PAGE=$((PAGE + 1))
  # The declared ceiling from capabilities.json. Exceeding it is a DOCUMENTED
  # truncation, not an error (CONTRACT.md "Adapter contract") — but it is never silent.
  if ((PAGE * WIT_GITEA_PAGE_SIZE > WIT_GITEA_LIST_ITEMS_MAX)); then
    printf 'list-items.sh: reached the declared ceiling of %s items for %s; results are truncated\n' \
      "$WIT_GITEA_LIST_ITEMS_MAX" "$REPO" >&2
    break
  fi
done

# Open-blocker counts are one request per item: Gitea's Issue carries no dependency
# data and there is no bulk dependency endpoint. Returning 0 instead would be worse
# than slow — list-frontier filters on blocked_by_count == 0, so every blocked item
# would surface as available work.
ITEMS='[]'
while IFS= read -r raw; do
  [[ -n "$raw" ]] || continue
  NUMBER="$(jq -r '.number' <<<"$raw")"
  # The helper exits on transport/HTTP failure, but inside $( ) that only ends the
  # subshell — propagate its code rather than continuing with "" and reporting a 401 or
  # a 503 as this adapter's own internal error.
  BBC="$(wit_gitea_blocked_by_count "$WIT_GITEA_OWNER" "$WIT_GITEA_REPO" "$NUMBER")" || exit "$?"
  ONE="$(jq -c --arg sv "$WIT_SCHEMA_VERSION" --argjson bbc "$BBC" \
    --arg full "$WIT_GITEA_OWNER/$WIT_GITEA_REPO" \
    '(.repository.full_name //= $full) | '"$WIT_GITEA_NORMALIZE_PROGRAM" <<<"$raw")" || {
    printf 'list-items.sh: could not normalize a gitea issue in %s\n' "$REPO" >&2
    exit "$EX_INTERNAL"
  }
  ITEMS="$(jq -c --argjson acc "$ITEMS" --argjson one "$ONE" '$acc + [$one]' <<<'null')"
done < <(jq -c '.[]' <<<"$COLLECTED")

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --argjson items "$ITEMS" \
  '{schema_version: $sv, items: $items}'
