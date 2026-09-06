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
#
# Rows travel through FILES, not shell variables. The earlier shape kept the accumulated
# array in a variable and re-serialized the whole of it through jq once per page and
# once per item, which is quadratic in the repository size, and it fed that variable to
# jq as a here-string, which on Git Bash blocks the shell forever once the payload
# reaches the pipe capacity (65536 bytes; see lib/hook-utils.sh hook::json_complete).
# Appending each page's issues to a file as one JSON object per line is linear, keeps
# every jq input off the command line (ARG_MAX) and out of here-strings, and lets the
# whole list be normalized in a single jq pass at the end.
if ! { ROWS="$(mktemp)" && COUNTS="$(mktemp)"; }; then
  printf 'list-items.sh: could not create temp files for the item walk\n' >&2
  exit "$EX_INTERNAL"
fi
trap 'rm -f "$ROWS" "$COUNTS"' EXIT

PAGE=1
# SEEN counts raw rows returned so far, for comparison against gitea's own X-Total-Count.
# `services/convert.ToCorrectPageSize` silently clamps `limit` to `[api] MAX_RESPONSE_ITEMS`
# (stock 50), so on an instance whose cap is below config.gitea.page_size EVERY page comes
# back short — "short page means last page" alone would end the loop after page 1 and return
# a truncated list with nothing said, with the ceiling guard below never firing either.
# This endpoint's handler calls ctx.SetTotalCountHeader, so when the header is present it is
# the authoritative end-of-list signal and the clamp stops mattering. The short-page heuristic
# stays as the fallback for anything that does not send one; it costs no extra request.
SEEN=0
while :; do
  # `type=issues` is a real query parameter on this endpoint (enum: issues|pulls). Without it
  # gitea returns pull requests too, which are then dropped below — so PRs consumed the page
  # budget and, worse, the declared ceiling counted rows rather than items, making a PR-heavy
  # repo report "reached the declared ceiling of 1000 items" having collected far fewer.
  wit_gitea_http GET "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/issues?state=$STATE&type=issues&page=$PAGE&limit=$WIT_GITEA_PAGE_SIZE"
  wit_gitea_require_ok "listing issues in $REPO"
  GOT="$(printf '%s' "$WIT_GITEA_BODY" | jq 'length' 2>/dev/null)" || {
    printf 'list-items.sh: gitea returned a non-array issue list for %s\n' "$REPO" >&2
    exit "$EX_INTERNAL"
  }
  # Belt and braces: `type=issues` should mean gitea sends no PRs, but a PR arriving as a work
  # item would be claimed and worked like one, so the filter stays. A page that will not
  # append is fatal: continuing would report a partial list as complete.
  printf '%s' "$WIT_GITEA_BODY" | jq -c '.[] | select(.pull_request == null)' >>"$ROWS" || {
    printf 'list-items.sh: could not accumulate page %s for %s — refusing to report a partial list as complete\n' \
      "$PAGE" "$REPO" >&2
    exit "$EX_INTERNAL"
  }
  SEEN=$((SEEN + GOT))
  ((GOT == 0)) && break
  if [[ -n "$WIT_GITEA_TOTAL_COUNT" ]]; then
    # Authoritative: stop when gitea says we have them all. An EMPTY header is "no count was
    # sent", never zero — hence the -n test rather than an arithmetic compare, which would
    # read a missing header as "0 items" and end the listing on its first pass.
    ((SEEN >= WIT_GITEA_TOTAL_COUNT)) && break
  else
    ((GOT < WIT_GITEA_PAGE_SIZE)) && break
  fi
  PAGE=$((PAGE + 1))
  # The declared ceiling from capabilities.json. Exceeding it is a DOCUMENTED truncation, not
  # an error (CONTRACT.md "Adapter contract") — but it is never silent. Measured against rows
  # ACTUALLY RETURNED, not against `PAGE * page_size`: under the clamp this whole change is
  # about, those two diverge. With page_size 100 against a server capping at 50, the requested
  # arithmetic reaches 1000 after ten pages that returned only 500 issues, so the walk stopped
  # half way and announced it had hit a ceiling it never reached.
  if ((SEEN > WIT_GITEA_LIST_ITEMS_MAX)); then
    printf 'list-items.sh: reached the declared ceiling of %s items for %s; results are truncated\n' \
      "$WIT_GITEA_LIST_ITEMS_MAX" "$REPO" >&2
    break
  fi
done

# Open-blocker counts are one request per item: Gitea's Issue carries no dependency
# data and there is no bulk dependency endpoint. Returning 0 instead would be worse
# than slow — list-frontier filters on blocked_by_count == 0, so every blocked item
# would surface as available work.
#
# The item numbers come out of the rows file in ONE jq pass, and each count is written
# beside its number as a JSON line; the final pass below joins the two files by number.
# So the per-item cost is the dependency request itself, not that plus three more jq
# processes to re-read, normalize and re-accumulate the item.
while IFS= read -r NUMBER; do
  # The number reaches a request path and is the join key below, so anything but digits
  # is refused here, before it can be interpolated or mis-joined.
  [[ "$NUMBER" =~ ^[0-9]+$ ]] || {
    printf 'list-items.sh: gitea returned an issue in %s without a numeric number: %s\n' "$REPO" "$NUMBER" >&2
    exit "$EX_INTERNAL"
  }
  # The helper exits on transport/HTTP failure, but inside $( ) that only ends the
  # subshell — propagate its code rather than continuing with "" and reporting a 401 or
  # a 503 as this adapter's own internal error.
  BBC="$(wit_gitea_blocked_by_count "$WIT_GITEA_OWNER" "$WIT_GITEA_REPO" "$NUMBER")" || exit "$?"
  printf '{"number":%s,"blocked_by_count":%s}\n' "$NUMBER" "$BBC" >>"$COUNTS"
done < <(jq -r '.number' "$ROWS")

# One pass builds the envelope: slurp the rows, join each to its blocker count, normalize.
# jq materializes the envelope before printing any of it, so a failure here (including a
# row with no count, which `error` turns into one) emits nothing rather than a truncated
# or partial envelope with a success status.
jq -c -s --slurpfile counts "$COUNTS" --arg sv "$WIT_SCHEMA_VERSION" \
  --arg full "$WIT_GITEA_OWNER/$WIT_GITEA_REPO" '
  ($counts | map({key: (.number | tostring), value: .blocked_by_count}) | from_entries) as $bbc_by_number
  | {schema_version: $sv,
     items: [ .[]
       | (.repository.full_name //= $full)
       | ($bbc_by_number[.number | tostring]) as $bbc
       | if $bbc == null then error("no blocker count for issue " + (.number | tostring)) else . end
       | '"$WIT_GITEA_NORMALIZE_PROGRAM"' ]}' "$ROWS" || {
  printf 'list-items.sh: could not normalize the gitea issues in %s — refusing to report a partial list as complete\n' "$REPO" >&2
  exit "$EX_INTERNAL"
}
