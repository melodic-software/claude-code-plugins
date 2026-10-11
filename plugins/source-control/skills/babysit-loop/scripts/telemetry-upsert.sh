#!/usr/bin/env bash
# telemetry-upsert.sh — maintain this babysit-loop instance's ONE sentinel-identified
# telemetry comment on the lane's tracking issue, and confirm the write landed.
#
# Usage:
#   telemetry-upsert.sh --repo OWNER/REPO --issue N --instance ID --body-file PATH [--app-slug SLUG]
#   telemetry-upsert.sh --repo OWNER/REPO --issue N --instance ID --read [--app-slug SLUG]
#
#   --read          print this identity's canonical comment body (empty when it has
#                   none) and write nothing; the re-anchor read of the state block.
#   --app-slug SLUG the GitHub App whose installation token gh runs under; its
#                   writes land as SLUG[bot].
#
# Only comments written by this script's own write identity count, whoever else
# posts the public sentinel. The identity is the `gh api user` login when that call
# reports a User; when it fails (an App installation token cannot call it) or
# reports a Bot, it is SLUG[bot] from --app-slug, else the reported Bot login with
# its [bot] suffix. Unresolved: exit 5, nothing read or written.
#
#   --instance ID   lane instance id, ^[a-z0-9][a-z0-9-]{0,31}$. Empty, or a literal
#                   unsubstituted ${user_config.…} placeholder, falls back to the
#                   lowercased hostname with every other character turned into `-`;
#                   the fallback is logged and passes through the same check.
#   --body-file PATH  this cycle's telemetry (report + state block). The script
#                   writes the sentinel line above it; a file that already opens with
#                   this instance's sentinel is sent as-is.
#
# Steps: pre-write body gate; write identity; paginated lookup of that identity's
# comments opening with the sentinel;
# POST when none exists, then re-list; PATCH the lowest id (canonical); read the
# comment back and byte-compare it with the body sent (CR and trailing newlines
# stripped from both sides, nothing else); only then tombstone duplicate sentinel
# comments, so an unconfirmed cycle never retires a racing session's comment.
#
# Exit codes (every non-zero exit means this cycle's telemetry is NOT confirmed;
# the caller records the lane as UNREPORTED and carries that to the next cycle):
#   0  written and the read-back matches the body sent byte for byte
#   3  invalid input or a body that failed the pre-write gate — nothing written
#   4  gh not found — nothing written
#   5  a gh call failed before anything verifiable landed: the write identity or
#      the lookup (nothing written), the POST, or the PATCH (the comment holds an
#      earlier body), or the POST landed under another login (a wrong
#      --app-slug); under --read, the identity, lookup, or read failed
#   6  the write was sent but is unconfirmed: the created comment was not re-found,
#      the read-back failed, or what was stored differs from what was sent
# A failed duplicate tombstone after a verified write is reported on stderr only;
# the next cycle retries it.

set -uo pipefail

die() {
  local code="$1"
  shift
  printf 'telemetry: %s\n' "$*" >&2
  exit "$code"
}

REPO="" ISSUE="" INSTANCE="" BODY_FILE="" APP_SLUG="" READ=""
while (($#)); do
  if [[ "$1" == --read ]]; then
    READ=1
    shift
    continue
  fi
  [[ "$1" == --repo || "$1" == --issue || "$1" == --instance || "$1" == --body-file || "$1" == --app-slug ]] ||
    die 3 "unknown argument: $1"
  (($# >= 2)) || die 3 "$1 requires a value"
  case "$1" in
    --repo) REPO="$2" ;;
    --issue) ISSUE="$2" ;;
    --instance) INSTANCE="$2" ;;
    --app-slug) APP_SLUG="$2" ;;
    *) BODY_FILE="$2" ;;
  esac
  shift 2
done

type -P gh >/dev/null 2>&1 || die 4 "gh not found; nothing written"

[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ && ! "/$REPO/" =~ /\.+/ ]] ||
  die 3 "--repo must be owner/repo (got '$REPO'); nothing written"
[[ "$ISSUE" =~ ^[1-9][0-9]*$ ]] || die 3 "--issue must be a positive integer (got '$ISSUE'); nothing written"
[[ -z "$APP_SLUG" || "$APP_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
  die 3 "--app-slug must be a GitHub App slug (got '$APP_SLUG'); nothing written"

if [[ -z "$INSTANCE" || "$INSTANCE" == "\${"* ]]; then
  INSTANCE="$(hostname | tr '[:upper:]' '[:lower:]' | tr -d '\r\n' | tr -c 'a-z0-9-' '-')"
  printf 'telemetry: lane_instance unset; assuming hostname-derived id %s\n' "$INSTANCE" >&2
fi
# Rejected, never trimmed into something that looks valid.
[[ "$INSTANCE" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] ||
  die 3 "lane_instance '$INSTANCE' is not ^[a-z0-9][a-z0-9-]{0,31}\$; refusing to build a marker"

SENT="<!-- harness-ops:lane-telemetry marker=source-control:babysit-loop@$INSTANCE -->"

# The write identity: whose comments this instance may adopt, edit, or tombstone.
# A User login is the identity; a failed call or a Bot means an App token, whose
# writes land as <slug>[bot]. Validated before it enters a jq program.
resolve_identity() {
  local who
  if who="$(gh api user --jq '.login + " " + .type' 2>/dev/null)" && [[ "$who" == *" User" ]]; then
    ME="${who% User}"
  elif [[ -n "$APP_SLUG" ]]; then
    ME="${APP_SLUG}[bot]"
  elif [[ "$who" == *" Bot" ]]; then
    ME="${who% Bot}"
    [[ "$ME" == *"[bot]" ]] || ME="${ME}[bot]"
  else
    return 1
  fi
  [[ "$ME" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*(\[bot\])?$ ]]
}

lookup() {
  gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" \
    --jq ".[] | select(.user.login == \"$ME\" and (.body | startswith(\"$SENT\"))) | .id"
}

canonical() { printf '%s\n' "$1" | grep -E '^[0-9]+$' | sort -n | head -n1; }

ME=""
need_identity() {
  resolve_identity ||
    die 5 "cannot resolve the write identity (gh api user failed or reported no User; pass --app-slug under an App token); nothing written"
}

if [[ -n "$READ" ]]; then
  need_identity
  LIST="$(lookup)" || die 5 "comment lookup failed; nothing read (fail closed)"
  CANON="$(canonical "$LIST")"
  [[ -z "$CANON" ]] && exit 0
  BACK="$(gh api "repos/$REPO/issues/comments/$CANON" --jq '.body')" ||
    die 5 "reading comment $CANON failed (fail closed)"
  printf '%s\n' "${BACK//$'\r'/}"
  exit 0
fi

[[ -f "$BODY_FILE" ]] || die 3 "body file not found: '$BODY_FILE'; nothing written"
body="$(tr -d '\r' <"$BODY_FILE")"
[[ -n "$body" && "$body" != @* ]] ||
  die 3 "body is empty or a literal @path - nothing written; fix the body composition, do not re-run blind"
[[ "${body%%$'\n'*}" == "$SENT" ]] && body="${body#*$'\n'}"
[[ "$body" == "$SENT" ]] && body=""
(($(printf '%s' "$body" | wc -c) >= 16)) ||
  die 3 "body carries under 16 payload bytes below the sentinel - nothing written; fix the body composition, do not re-run blind"
SENT_BODY="$SENT"$'\n'"$body"

SEND_FILE="$(mktemp)" || die 3 "cannot create a temporary file; nothing written"
trap 'rm -f "$SEND_FILE"' EXIT
printf '%s\n' "$SENT_BODY" >"$SEND_FILE"

need_identity

LIST="$(lookup)" || die 5 "comment lookup failed; nothing written this cycle (fail closed)"
if [[ -z "$LIST" ]]; then
  POSTED_AS="$(gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$SEND_FILE" --jq '.user.login')" ||
    die 5 "creating the telemetry comment failed; nothing written"
  # A wrong --app-slug would otherwise post a fresh, never-found comment every cycle.
  [[ "$POSTED_AS" == "$ME" ]] ||
    die 5 "the comment was posted as '$POSTED_AS', not the resolved write identity '$ME'; fix --app-slug before the next cycle"
  LIST="$(lookup)" || LIST=""
fi
CANON="$(canonical "$LIST")"
[[ -n "$CANON" ]] ||
  die 6 "a create was sent but no telemetry comment was re-found; the write is unconfirmed"

gh api -X PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$SEND_FILE" >/dev/null ||
  die 5 "the PATCH of comment $CANON failed; the comment holds an earlier body, not this cycle's"

BACK="$(gh api "repos/$REPO/issues/comments/$CANON" --jq '.body')" ||
  die 6 "re-reading comment $CANON failed; this cycle's write is unconfirmed"
BACK="${BACK//$'\r'/}"
[[ "$BACK" == "$SENT_BODY" ]] ||
  die 6 "comment $CANON does not hold the body this cycle sent (stale, overwritten, or mangled); do not trust its timestamp"

for DUP in $(printf '%s\n' "$LIST" | grep -E '^[0-9]+$' | sort -n | tail -n +2); do
  gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
    -f body="Superseded duplicate - canonical telemetry comment: $CANON" >/dev/null ||
    printf 'telemetry: tombstoning duplicate comment %s failed; the next cycle retries it\n' "$DUP" >&2
done
printf 'telemetry: comment %s verified (marker=source-control:babysit-loop@%s)\n' "$CANON" "$INSTANCE"
