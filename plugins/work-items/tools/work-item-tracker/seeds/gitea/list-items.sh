#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: list-items.sh [--state open|closed|all] [--repo <o>/<r>] [--label <name>]'
wit_help_if_requested "$USAGE" "$@"

STATE="open"
REPO=""
LABEL_QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --state)
    [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
    STATE="$2"
    shift 2
    ;;
  --label)
    [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--label needs a value"
    LABEL_QUERY="&labels=$(jq -rn --arg l "$2" '$l | @uri')"
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

if [[ -z "$REPO" ]]; then
  if [[ "$(jq 'length' <<<"$WIT_GITEA_SCOPES")" != "1" ]]; then
    wit_usage_error "--repo is required when config.gitea.scopes declares more than one repository"
  fi
  REPO="$(jq -r '.[0]' <<<"$WIT_GITEA_SCOPES")"
fi
[[ "$REPO" =~ $WIT_GITEA_SCOPE_RE ]] ||
  wit_usage_error "--repo must be <owner>/<repo>: $REPO"
wit_gitea_scope_in_scope "$REPO" ||
  wit_usage_error "$REPO is not in config.gitea.scopes (the declared read scope)"
wit_gitea_scope_parts "$REPO"

if ! { ROWS="$(mktemp)" && COUNTS="$(mktemp)"; }; then
  printf 'list-items.sh: could not create temp files for the item walk\n' >&2
  exit "$EX_INTERNAL"
fi
trap 'rm -f "$ROWS" "$COUNTS"' EXIT

PAGE=1
SEEN=0
TRUNCATED=false
while :; do
  wit_gitea_http GET "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/issues?state=$STATE&type=issues$LABEL_QUERY&page=$PAGE&limit=$WIT_GITEA_PAGE_SIZE"
  wit_gitea_require_ok "listing issues in $REPO"
  GOT="$(printf '%s' "$WIT_GITEA_BODY" | jq 'length' 2>/dev/null)" || {
    printf 'list-items.sh: gitea returned a non-array issue list for %s\n' "$REPO" >&2
    exit "$EX_INTERNAL"
  }
  printf '%s' "$WIT_GITEA_BODY" | jq -c '.[] | select(.pull_request == null)' >>"$ROWS" || {
    printf 'list-items.sh: could not accumulate page %s for %s — refusing to report a partial list as complete\n' \
      "$PAGE" "$REPO" >&2
    exit "$EX_INTERNAL"
  }
  SEEN=$((SEEN + GOT))
  ((GOT == 0)) && break
  if [[ -n "$WIT_GITEA_TOTAL_COUNT" ]]; then
    ((SEEN >= WIT_GITEA_TOTAL_COUNT)) && break
  else
    ((GOT < WIT_GITEA_PAGE_SIZE)) && break
  fi
  PAGE=$((PAGE + 1))
  if ((SEEN > WIT_GITEA_LIST_ITEMS_MAX)); then
    printf 'list-items.sh: reached the declared ceiling of %s items for %s; results are truncated\n' \
      "$WIT_GITEA_LIST_ITEMS_MAX" "$REPO" >&2
    TRUNCATED=true
    break
  fi
done

while IFS= read -r NUMBER; do
  [[ "$NUMBER" =~ ^(0|[1-9][0-9]*)$ ]] || {
    printf 'list-items.sh: gitea returned an issue in %s without a numeric number: %s\n' "$REPO" "$NUMBER" >&2
    exit "$EX_INTERNAL"
  }
  BBC="$(wit_gitea_blocked_by_count "$WIT_GITEA_OWNER" "$WIT_GITEA_REPO" "$NUMBER")" || exit "$?"
  printf '{"number":%s,"blocked_by_count":%s}\n' "$NUMBER" "$BBC" >>"$COUNTS"
done < <(jq -r '.number' "$ROWS")

jq -c -s --slurpfile counts "$COUNTS" --arg sv "$WIT_SCHEMA_VERSION" \
  --arg full "$WIT_GITEA_OWNER/$WIT_GITEA_REPO" --argjson truncated "$TRUNCATED" '
  ($counts | map({key: (.number | tostring), value: .blocked_by_count}) | from_entries) as $bbc_by_number
  | {schema_version: $sv,
     items: [ .[]
       | (.repository.full_name //= $full)
       | ($bbc_by_number[.number | tostring]) as $bbc
       | if $bbc == null then error("no blocker count for issue " + (.number | tostring)) else . end
       | '"$WIT_GITEA_NORMALIZE_PROGRAM"' ],
     truncated: $truncated}' "$ROWS" || {
  printf 'list-items.sh: could not normalize the gitea issues in %s; refusing to report a partial list as complete\n' "$REPO" >&2
  exit "$EX_INTERNAL"
}
