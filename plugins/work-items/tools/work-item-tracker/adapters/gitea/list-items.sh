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
  GOT="$(jq 'length' <<<"$WIT_GITEA_BODY" 2>/dev/null)" || {
    printf 'list-items.sh: gitea returned a non-array issue list for %s\n' "$REPO" >&2
    exit "$EX_INTERNAL"
  }
  # Belt and braces: `type=issues` should mean gitea sends no PRs, but a PR arriving as a work
  # item would be claimed and worked like one, so the filter stays.
  # The ACCUMULATOR travels on stdin and only the (page-size-bounded) page travels in argv.
  # The other way round — `--argjson acc "$COLLECTED"` — puts an unboundedly growing array on
  # jq's command line, and past ARG_MAX the kernel refuses the exec: jq dies with "Argument
  # list too long", the unchecked assignment leaves COLLECTED empty, and list-items reports
  # ZERO issues while exiting 0. A big repo silently looked empty.
  COLLECTED="$(jq -c --argjson page "$WIT_GITEA_BODY" \
    '. + [ $page[] | select(.pull_request == null) ]' <<<"$COLLECTED")" || {
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
  # Accumulator on stdin, one item in argv — see the note on the page accumulation above.
  ITEMS="$(jq -c --argjson one "$ONE" '. + [$one]' <<<"$ITEMS")" || {
    printf 'list-items.sh: could not accumulate a normalized issue in %s — refusing to report a partial list as complete\n' "$REPO" >&2
    exit "$EX_INTERNAL"
  }
done < <(jq -c '.[]' <<<"$COLLECTED")

# The envelope is built with ITEMS on STDIN for the same ARG_MAX reason as the accumulation
# above — this is the one place where the array is guaranteed to be at its largest, so it is
# the likeliest to blow the command line. A failure here must not emit a truncated or empty
# envelope with a success status.
jq -c --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: .}' <<<"$ITEMS" || {
  printf 'list-items.sh: could not emit the item envelope for %s\n' "$REPO" >&2
  exit "$EX_INTERNAL"
}
