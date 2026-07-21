#!/usr/bin/env bash
# telemetry-upsert.sh — maintain exactly ONE marker-identified comment on a
# tracking issue, editing it in place every cycle instead of posting a second.
#
# The loop-lane contract "maintain ONE telemetry comment, EDIT it in place, never
# post a second" is otherwise a prose warning every lane prompt has to carry — the
# tell that marker-based edit-in-place is deterministic work that belongs in a
# script, not repeated reasoning (issue #538, item 2; interim home of the #502
# telemetry comment).
#
# MARKER / DETECTION CONVENTION (reusable across lanes and tracking issues):
#   The script writes a machine-detectable sentinel as the FIRST line of the
#   comment body:
#       <!-- claude-ops:lane-telemetry marker=<MARKER> -->
#   <MARKER> is a caller-supplied short id (e.g. `lane:triage`) constrained to
#   [A-Za-z0-9:._-] so it can never contain the `>` that would close the comment
#   early. The sentinel is an HTML comment: invisible in the rendered issue, and
#   distinct per marker, so N lanes can each own one comment on the SAME issue
#   without colliding. Upsert = find that sentinel and PATCH it, else create it.
#
#   Detection is two-tier (mirrors the issue's spec):
#     1. Primary — a comment whose body contains the exact sentinel above. The
#        newest such comment wins if (abnormally) several exist.
#     2. Fallback — no sentinel yet (first migration off a hand-authored comment):
#        the most recent comment BY THE AUTHENTICATED USER whose body contains the
#        raw <MARKER> text. PATCHing it adopts it (adds the sentinel), so the next
#        cycle takes the primary path. This is why the fallback is user-scoped:
#        editing another author's comment is neither possible via the API nor
#        intended, and a single writer identity owns a given marker.
#
# Usage:
#   telemetry-upsert.sh --issue N --marker STR --body-file PATH [--repo owner/name]
#                       [--dry-run]
#
#   --issue N        Tracking issue number (required).
#   --marker STR     Marker id, [A-Za-z0-9:._-]+ (required).
#   --body-file PATH File whose contents become the comment body BELOW the
#                    sentinel (required; `-` reads stdin). Kept small — a
#                    telemetry block, not an essay.
#   --repo owner/name  Target repo (default: `gh repo view` for the cwd's repo).
#   --dry-run        Resolve + report the action (create/update + target id) but
#                    perform no write.
#   --help
#
# Output (stdout): one action line, e.g.
#   telemetry-upsert: updated comment 12345 (marker=lane:triage) on <owner/repo>#502
#   <html_url>
#
# Exit codes:
#   0  upserted (or, with --dry-run, resolved)
#   3  invalid argument
#   4  prerequisite missing (gh or jq) or repo could not be resolved
#   5  a gh API call (list / create / update) failed

set -uo pipefail

jq() { command jq "$@" | tr -d '\r'; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    err "$bin not found (required)"
    exit 4
  }
done

ISSUE=""
MARKER=""
BODY_FILE=""
REPO=""
DRY_RUN=0
while (($#)); do
  case "$1" in
  --issue)
    ISSUE="${2:-}"
    shift 2
    ;;
  --issue=*)
    ISSUE="${1#*=}"
    shift
    ;;
  --marker)
    MARKER="${2:-}"
    shift 2
    ;;
  --marker=*)
    MARKER="${1#*=}"
    shift
    ;;
  --body-file)
    BODY_FILE="${2:-}"
    shift 2
    ;;
  --body-file=*)
    BODY_FILE="${1#*=}"
    shift
    ;;
  --repo)
    REPO="${2:-}"
    shift 2
    ;;
  --repo=*)
    REPO="${1#*=}"
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown argument: $1"
    exit 3
    ;;
  esac
done

[[ "$ISSUE" =~ ^[0-9]+$ ]] || {
  err "--issue must be a positive integer (got: '${ISSUE:-}')"
  exit 3
}
[[ "$MARKER" =~ ^[A-Za-z0-9:._-]+$ ]] || {
  err "--marker must match [A-Za-z0-9:._-]+ (got: '${MARKER:-}')"
  exit 3
}
[[ -n "$BODY_FILE" ]] || {
  err "--body-file is required"
  exit 3
}

# Read the body (a `-` reads stdin, matching common CLI convention).
if [[ "$BODY_FILE" == "-" ]]; then
  body_text="$(cat)"
else
  [[ -f "$BODY_FILE" ]] || {
    err "body file not found: $BODY_FILE"
    exit 3
  }
  body_text="$(cat "$BODY_FILE")"
fi

SENTINEL="<!-- claude-ops:lane-telemetry marker=$MARKER -->"
new_body="$SENTINEL"$'\n'"$body_text"

# --- Resolve owner/repo ------------------------------------------------------
if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null | tr -d '\r')"
  [[ -n "$REPO" ]] || {
    err "could not resolve repo (run inside a gh repo or pass --repo owner/name)"
    exit 4
  }
fi

# --- List existing comments (paginated, raw) ---------------------------------
# Fetch raw JSON and select in-script rather than via `gh --jq`, so the whole
# two-tier detection is one auditable jq program. --paginate concatenates one
# JSON array per page; `jq -s 'add'` slurps them into a single array — without
# it, an existing comment on page 2 of a busy tracking issue is invisible and we
# would POST a duplicate, the exact failure this script exists to prevent.
raw_pages="$(gh api --paginate "repos/$REPO/issues/$ISSUE/comments" 2>/dev/null)" || {
  err "failed to list comments on $REPO#$ISSUE (gh api)"
  exit 5
}
comments="$(jq -s 'add // []' <<<"$raw_pages" 2>/dev/null)" || comments='[]'

# Primary: newest comment carrying the exact sentinel.
target_id="$(jq -r --arg s "$SENTINEL" '
  [ .[] | select(.body // "" | contains($s)) ] | sort_by(.created_at) | last | .id // empty
' <<<"$comments")"
detect="sentinel"

# Fallback: no sentinel yet — the newest of MY comments containing the raw marker.
if [[ -z "$target_id" ]]; then
  me="$(gh api user --jq '.login' 2>/dev/null | tr -d '\r')"
  if [[ -n "$me" ]]; then
    target_id="$(jq -r --arg m "$MARKER" --arg me "$me" '
      [ .[] | select((.user.login // "") == $me and ((.body // "") | contains($m))) ]
      | sort_by(.created_at) | last | .id // empty
    ' <<<"$comments")"
    [[ -n "$target_id" ]] && detect="marker-fallback"
  fi
fi

# --- Act ---------------------------------------------------------------------
if [[ -n "$target_id" ]]; then
  action="update"
  if ((DRY_RUN)); then
    printf 'telemetry-upsert: DRY-RUN would update comment %s (marker=%s, matched via %s) on %s#%s\n' \
      "$target_id" "$MARKER" "$detect" "$REPO" "$ISSUE"
    exit 0
  fi
  resp="$(gh api --method PATCH "repos/$REPO/issues/comments/$target_id" -f body="$new_body" 2>/dev/null)" || {
    err "failed to update comment $target_id on $REPO#$ISSUE (gh api PATCH) — comment author must match the authenticated user"
    exit 5
  }
else
  action="create"
  if ((DRY_RUN)); then
    printf 'telemetry-upsert: DRY-RUN would create a new comment (marker=%s) on %s#%s\n' \
      "$MARKER" "$REPO" "$ISSUE"
    exit 0
  fi
  resp="$(gh api --method POST "repos/$REPO/issues/$ISSUE/comments" -f body="$new_body" 2>/dev/null)" || {
    err "failed to create comment on $REPO#$ISSUE (gh api POST)"
    exit 5
  }
fi

new_id="$(jq -r '.id // empty' <<<"$resp")"
html_url="$(jq -r '.html_url // empty' <<<"$resp")"
printf 'telemetry-upsert: %sd comment %s (marker=%s) on %s#%s\n' \
  "$action" "${new_id:-?}" "$MARKER" "$REPO" "$ISSUE"
[[ -n "$html_url" ]] && printf '%s\n' "$html_url"
