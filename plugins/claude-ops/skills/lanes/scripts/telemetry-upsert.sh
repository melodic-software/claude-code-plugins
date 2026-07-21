#!/usr/bin/env bash
# telemetry-upsert.sh — maintain exactly ONE marker-identified comment on a
# tracking issue, editing it in place every cycle instead of posting a second.
#
# The loop-lane contract "maintain ONE telemetry comment, EDIT it in place, never
# post a second" is otherwise a prose warning every lane prompt has to carry — the
# tell that marker-based edit-in-place is deterministic work that belongs in a
# script, not repeated reasoning. It is the interim scripted home of the per-lane
# telemetry-comment contract.
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
#   telemetry-upsert.sh --issue N --marker STR --body-file PATH
#                       [--body-dir DIR] [--repo owner/name] [--dry-run]
#
#   --issue N        Tracking issue number (required).
#   --marker STR     Marker id, [A-Za-z0-9:._-]+ (required).
#   --body-file PATH File whose contents become the comment body BELOW the
#                    sentinel (required; `-` reads stdin). Kept small — a
#                    telemetry block, not an essay (hard cap: 64 KiB).
#                    SECURITY: a real path (not `-`) MUST resolve under the safe
#                    body dir (--body-dir, else $CLAUDE_PLUGIN_DATA). This script
#                    is driven by AI lane prompts; an unconstrained path read
#                    would let a prompt-injected `--body-file ~/.ssh/id_rsa` (or a
#                    token store / .env) be posted verbatim as a public comment —
#                    silent credential exfiltration. Containment blocks that; pipe
#                    via `-` for a body generated in memory.
#   --body-dir DIR   Directory a real --body-file must resolve under
#                    (default: $CLAUDE_PLUGIN_DATA).
#   --repo owner/name  Target repo (default: `gh repo view` for the cwd's repo).
#                    Validated as owner/repo before URL interpolation so a
#                    traversal value can't redirect the API to another repo.
#   --dry-run        Resolve + report the action (create/update + target id) but
#                    perform no write.
#   --help
#
# Output (stdout): one action line, e.g.
#   telemetry-upsert: updated comment 12345 (marker=lane:triage) on <owner/repo>#<issue>
#   <html_url>
#
# Exit codes:
#   0  upserted (or, with --dry-run, resolved)
#   3  invalid argument (bad issue/marker/repo, body-file outside the safe dir,
#      or a body over the size cap)
#   4  prerequisite missing (gh or jq), or the repo / safe body dir unresolved
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

MAX_BODY_BYTES=65536 # 64 KiB — a telemetry body, not an essay

ISSUE=""
MARKER=""
BODY_FILE=""
BODY_DIR=""
REPO=""
DRY_RUN=0
while (($#)); do
  case "$1" in
  --issue)
    [[ $# -ge 2 ]] || {
      err "--issue requires a value"
      exit 3
    }
    ISSUE="$2"
    shift 2
    ;;
  --issue=*)
    ISSUE="${1#*=}"
    shift
    ;;
  --marker)
    [[ $# -ge 2 ]] || {
      err "--marker requires a value"
      exit 3
    }
    MARKER="$2"
    shift 2
    ;;
  --marker=*)
    MARKER="${1#*=}"
    shift
    ;;
  --body-file)
    [[ $# -ge 2 ]] || {
      err "--body-file requires a value"
      exit 3
    }
    BODY_FILE="$2"
    shift 2
    ;;
  --body-file=*)
    BODY_FILE="${1#*=}"
    shift
    ;;
  --body-dir)
    [[ $# -ge 2 ]] || {
      err "--body-dir requires a value"
      exit 3
    }
    BODY_DIR="$2"
    shift 2
    ;;
  --body-dir=*)
    BODY_DIR="${1#*=}"
    shift
    ;;
  --repo)
    [[ $# -ge 2 ]] || {
      err "--repo requires a value"
      exit 3
    }
    REPO="$2"
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

# Read the body. `-` reads stdin (a body generated in memory — no arbitrary-file
# read, so it is exempt from the containment check below). A real path must
# resolve UNDER the safe dir: this script is prompt-driven, and an unconstrained
# read would turn `--body-file <any-secret>` into public-comment exfiltration.
if [[ "$BODY_FILE" == "-" ]]; then
  body_text="$(cat)"
else
  [[ -f "$BODY_FILE" ]] || {
    err "body file not found: $BODY_FILE"
    exit 3
  }
  # Reject a symlink leaf outright. Containment below canonicalizes the PARENT
  # dir but re-appends the basename raw, so a symlink whose link file sits under
  # the safe dir but targets a secret elsewhere would otherwise pass and `cat`
  # would follow it. A telemetry body has no reason to be a symlink; use `-`
  # (stdin) for an in-memory body.
  [[ -L "$BODY_FILE" ]] && {
    err "body file must not be a symlink: $BODY_FILE"
    exit 3
  }
  safe_dir="${BODY_DIR:-${CLAUDE_PLUGIN_DATA:-}}"
  [[ -n "$safe_dir" ]] || {
    err "no safe body dir: set \$CLAUDE_PLUGIN_DATA or pass --body-dir DIR (or pipe the body via --body-file -)"
    exit 4
  }
  # Canonicalize the PARENT dir of each side to a physical path via the same
  # `cd … && pwd -P` (resolving any `..` and symlinked ancestor), then compare
  # prefixes. The leaf is guarded separately by the symlink check above, so
  # re-appending basename raw is safe.
  safe_canon="$(cd "$safe_dir" 2>/dev/null && pwd -P)" || {
    err "safe body dir not found: $safe_dir"
    exit 4
  }
  body_parent="$(cd "$(dirname "$BODY_FILE")" 2>/dev/null && pwd -P)" || {
    err "cannot resolve body file directory: $BODY_FILE"
    exit 3
  }
  body_canon="$body_parent/$(basename "$BODY_FILE")"
  # The trailing slash in the pattern forces a path-segment boundary, so
  # `/safe` never matches a sibling `/safe-evil/...`.
  case "$body_canon" in
  "$safe_canon"/*) : ;;
  *)
    err "body file must resolve under the safe dir ($safe_canon); refusing to read $body_canon"
    exit 3
    ;;
  esac
  body_text="$(cat "$BODY_FILE")"
fi

# Size guard (defense in depth), applied to file AND stdin bodies alike.
body_bytes="$(printf '%s' "$body_text" | wc -c | tr -d ' ')"
if ((body_bytes > MAX_BODY_BYTES)); then
  err "body is ${body_bytes} bytes, over the ${MAX_BODY_BYTES}-byte cap — telemetry bodies are small"
  exit 3
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

# Validate BEFORE interpolating $REPO into any gh api URL path. Both the explicit
# --repo value and the auto-detected one flow through here. Without this, a value
# like `foo/bar/../../org/target` injects `..` segments that GitHub's API routing
# normalizes, redirecting the GET/PATCH/POST to a different repo the token can
# reach. A single owner/repo pair (one slash, no traversal) is the only shape.
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || {
  err "--repo must be owner/repo (got: '$REPO')"
  exit 3
}

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

# Fallback: no sentinel yet — the newest of MY comments carrying the raw marker
# as a whole token. A plain substring match would let a shorter marker adopt a
# longer lane's comment: `lane:triage` is a prefix of `lane:triage-old`, so
# `contains("lane:triage")` matches the other lane's comment and this run would
# PATCH it — overwriting that lane's only telemetry comment. The lookaround
# boundaries (marker charset [A-Za-z0-9:._-]) require the marker not abut another
# marker-charset char on either side; `.` is escaped so it stays a literal.
if [[ -z "$target_id" ]]; then
  me="$(gh api user --jq '.login' 2>/dev/null | tr -d '\r')"
  if [[ -n "$me" ]]; then
    target_id="$(jq -r --arg m "$MARKER" --arg me "$me" '
      ($m | gsub("[.]"; "\\.")) as $mre
      | [ .[]
          | select((.user.login // "") == $me
              and ((.body // "") | test("(?<![A-Za-z0-9:._-])" + $mre + "(?![A-Za-z0-9:._-])"))) ]
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
