#!/usr/bin/env bash
# lane-telemetry-upsert.sh — maintain ONE sentinel-identified telemetry comment
# per lane instance on a lane's tracking issue, editing it in place every cycle.
#
# The loop-lane contract is "maintain ONE telemetry comment per writer identity,
# EDIT it in place, never post a second". This script owns the whole mechanism:
# lane-instance validation, marker construction, the pre-write body gate, the
# singleton lookup, the create/update, the post-write read-back, and the
# creation-race reconcile. The lane skills invoke it; they do not re-derive it.
#
# Usage:
#   lane-telemetry-upsert.sh --lane work-loop|attend-queue --instance <id> \
#     --repo <owner/name> --issue <n> --body-file <path>
#
#   --lane        Lane type. Names the marker's lane half.
#   --instance    Lane-instance id, ^[a-z0-9][a-z0-9-]{0,31}$. Names the WRITER,
#                 so two instances of one lane never clobber each other. An empty
#                 value, or a surviving literal ${user_config.…} placeholder,
#                 means the key is unset and falls back to the sanitized lowercased
#                 hostname; the fallback is validated by the same gate, so a
#                 hostname that cannot produce a conforming id stops the lane
#                 rather than yielding a marker nobody chose.
#   --repo        Target repository, owner/name. Validated before it reaches any
#                 API URL path, so a traversal value cannot redirect the write.
#   --issue       Tracking issue number.
#   --body-file   File whose contents become the comment body. Its FIRST line
#                 must be exactly the sentinel this script computes from the
#                 marker, with the cycle's telemetry below it, and at least 16
#                 payload bytes below line 1. The lookup matches on that prefix,
#                 so a body composed without it would never be found again and
#                 the next cycle would post a second comment.
#   --help
#
# MARKER. `work-items:<lane>@<instance>`, and the sentinel written as the body's
# first line is `<!-- claude-ops:lane-telemetry marker=<marker> -->`. The sentinel
# is an HTML comment: invisible when rendered, distinct per writer, so sibling
# instances each own one comment on the SAME issue without colliding.
#
# THREE CHECKS, because they catch different failures. The PRE-WRITE gate runs
# before any API call and rejects a body that is empty, opens with a literal `@`,
# is not sentinel-prefixed, or carries under 16 payload bytes below the sentinel.
# A body argument given an `@path` string posts the literal path text while the
# comment's timestamp still moves, so the surface reads FRESH while carrying no
# data. The WRITE'S OWN EXIT STATUS is checked next: a failed PATCH leaves the
# previous cycle's body in place, which a read-back running regardless would
# happily accept. The POST-WRITE read-back then re-reads what the write stored,
# the only check that sees a write which reported success and stored something
# else. It is also why create and update only ever use `-F body=@`: `-f body=@FILE`
# transmits the literal path.
#
# CREATION-RACE RECONCILE. Two sessions racing the first-ever upsert can both see
# an empty lookup and both POST, forking the singleton. Every cycle duplicates are
# visible, the LOWEST comment id is canonical (numeric sort, deterministic for
# every session), the canonical comment receives the current cycle's full state,
# and every other sentinel comment is edited to a one-line tombstone — only once
# the canonical write verifies, so a cycle whose own write is unproven never
# tombstones a racing session's comment. A crashed racer's unmerged counters are
# an accepted loss; nothing is deleted. The reconcile converges duplicates within
# ONE instance's own sentinel set; a sibling instance's comment carries a different
# marker and never enters the list.
#
# Exit codes. Codes 2-8 are caller errors; 9 and 10 mean NOTHING was written, so
# fix the body composition and do not re-run blind; 11-14 mean the lane is
# UNREPORTED for this cycle and must carry that forward, because stderr does not
# survive the session and the next cycle has to see that this one did not report.
# A non-zero exit is never a reason to end the loop or the pass.
#
#   0   upserted and verified; any duplicates superseded
#   2   usage: a missing, repeated, or unknown argument
#   3   --lane is not one of work-loop|attend-queue
#   4   the resolved lane instance is empty, starts with a hyphen, or carries a
#       character outside [a-z0-9-] — rejected, never trimmed into something
#       that looks valid
#   5   the resolved lane instance exceeds 32 characters (the length half of
#       ^[a-z0-9][a-z0-9-]{0,31}$, which code 4 enforces the shape half of)
#   6   --repo is not owner/name
#   7   --issue is not a positive integer
#   8   prerequisite missing: gh or jq is not on PATH
#   9   the body file is missing, empty, or opens with a literal `@` — NOTHING written
#   10  the body is not sentinel-prefixed, or carries under 16 payload bytes
#       below line 1 — NOTHING written
#   11  the comment lookup failed or returned unparsable JSON; the upsert is
#       skipped this cycle (fail closed — treating an unreadable list as empty
#       would post a second comment)
#   12  no comment available to write to; a create may have landed but was not
#       re-found — lane UNREPORTED
#   13  the PATCH of the canonical comment failed — lane UNREPORTED; the comment
#       holds an earlier body, not this cycle's write
#   14  the canonical comment does NOT carry a well-formed telemetry body after
#       the write — lane UNREPORTED; do not trust the timestamp
#
# KNOWN LIMITS. A PATCH that succeeds while storing the previous body still
# verifies: the read-back asserts that SOME well-formed telemetry is present, not
# that THIS cycle's write is what is present. Not implemented at all: the 64 KiB
# cap, body-file containment, and read retries that the `claude-ops` lanes wrapper
# carries. An installed plugin cannot invoke a sibling plugin's scripts, which is
# why this mechanism lives here rather than deferring to that wrapper.

set -uo pipefail

MIN_PAYLOAD_BYTES=16

err() { printf 'telemetry: %s\n' "$*" >&2; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

require_value() {
  (($# >= 2)) && return 0
  err "$1 requires a value"
  exit 2
}

LANE=""
INSTANCE=""
REPO=""
ISSUE=""
BODY_FILE=""
while (($#)); do
  case "$1" in
  --lane)
    require_value "$@"
    LANE="$2"
    shift 2
    ;;
  --lane=*)
    LANE="${1#*=}"
    shift
    ;;
  --instance)
    require_value "$@"
    INSTANCE="$2"
    shift 2
    ;;
  --instance=*)
    INSTANCE="${1#*=}"
    shift
    ;;
  --repo)
    require_value "$@"
    REPO="$2"
    shift 2
    ;;
  --repo=*)
    REPO="${1#*=}"
    shift
    ;;
  --issue)
    require_value "$@"
    ISSUE="$2"
    shift 2
    ;;
  --issue=*)
    ISSUE="${1#*=}"
    shift
    ;;
  --body-file)
    require_value "$@"
    BODY_FILE="$2"
    shift 2
    ;;
  --body-file=*)
    BODY_FILE="${1#*=}"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown argument: $1"
    exit 2
    ;;
  esac
done

[[ -n "$BODY_FILE" ]] || {
  err "--body-file is required"
  exit 2
}

case "$LANE" in
work-loop | attend-queue) : ;;
*)
  err "--lane must be work-loop or attend-queue (got: '$LANE')"
  exit 3
  ;;
esac

# A surviving literal placeholder means the userConfig key is unset, so it takes
# the same path as an absent value rather than being validated as an id.
# shellcheck disable=SC2016  # the placeholder is matched literally, never expanded
case "$INSTANCE" in
'${user_config.'*) INSTANCE="" ;;
*) : ;;
esac

# The hostname fallback is a DEFAULT, not a sanitizer: the gate below validates
# it exactly as it validates a supplied id. The transform is byte-for-byte the
# one the lanes have always used, because normalizing it would change the marker
# and orphan every comment written under the fallback.
if [[ -z "$INSTANCE" ]]; then
  INSTANCE="$(hostname | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
  err "no lane instance supplied; assuming the sanitized hostname '$INSTANCE'"
fi

# Validated and REJECTED, never sanitized-and-continued: this is operator-supplied
# text about to be interpolated into a marker, a shell string, and a jq program.
# The check runs BEFORE the marker is built, because a lane that validates only
# after the fact has a guard that does not guard.
case "$INSTANCE" in
"" | -* | *[!a-z0-9-]*)
  err "lane_instance '$INSTANCE' is not ^[a-z0-9][a-z0-9-]{0,31}\$; refusing to build a marker"
  exit 4
  ;;
*) : ;;
esac
if ((${#INSTANCE} > 32)); then
  err "lane_instance '$INSTANCE' exceeds 32 characters; refusing to build a marker"
  exit 5
fi

# Validated before it reaches any gh api URL path. A value carrying `..` segments
# would be normalized by GitHub's API routing and redirect the write to another
# repository the token can reach.
if [[ ! "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  err "--repo must be owner/name (got: '$REPO')"
  exit 6
fi
if [[ ! "$ISSUE" =~ ^[0-9]+$ ]]; then
  err "--issue must be a positive integer (got: '$ISSUE')"
  exit 7
fi

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    err "$bin not found (required)"
    exit 8
  }
done

MARKER="work-items:$LANE@$INSTANCE"
SENT="<!-- claude-ops:lane-telemetry marker=$MARKER -->"

# --- Pre-write body gate -----------------------------------------------------
if [[ ! -s "$BODY_FILE" ]]; then
  err "body is missing or empty - nothing written; fix the body composition, do not re-run blind"
  exit 9
fi
if [[ "$(head -c 1 "$BODY_FILE")" == "@" ]]; then
  err "body is a literal @path - nothing written; fix the body composition, do not re-run blind"
  exit 9
fi

BODY_TEXT="$(cat "$BODY_FILE")"

# Compared as a BYTE PREFIX, not as a whole first line: the payload floor is
# measured over everything below line 1, so the gate reads the same whether that
# line ends in LF or CRLF.
sentinel_ok() {
  local text="$1" head_bytes payload_bytes
  head_bytes="$(printf '%s' "$text" | head -c "${#SENT}")"
  [[ "$head_bytes" == "$SENT" ]] || return 1
  payload_bytes="$(printf '%s' "$text" | tail -n +2 | wc -c | tr -d ' ')"
  ((payload_bytes >= MIN_PAYLOAD_BYTES))
}

if ! sentinel_ok "$BODY_TEXT"; then
  err "body is not sentinel-prefixed or carries no payload - nothing written; fix the body composition, do not re-run blind"
  exit 10
fi

# --- Singleton lookup --------------------------------------------------------
# `--paginate` is what makes an existing comment on page 2 of a busy tracking
# issue visible; without it the lane would POST a duplicate every cycle. The
# match is `startswith` on the FULL sentinel, never `contains`, so a body that
# merely quotes a sibling instance's sentinel is not adopted.
lookup() {
  local pages ids
  pages="$(gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" 2>/dev/null)" || return 1
  ids="$(jq -r --arg s "$SENT" '[.[] | select((.body // "") | startswith($s)) | .id] | .[]' <<<"$pages" 2>/dev/null)" || return 1
  printf '%s\n' "$ids"
}

if ! LIST="$(lookup)"; then
  err "comment lookup failed; skipping upsert this cycle (fail closed)"
  exit 11
fi

if [[ -z "${LIST//[[:space:]]/}" ]]; then
  gh api --method POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE" >/dev/null 2>&1 || true
  # A failure re-listing here is not fatal: the create may have landed, and the
  # next cycle's ordinary upsert performs the same reconcile.
  LIST="$(lookup)" || LIST=""
fi

CANON="$(printf '%s\n' "$LIST" | grep -E '^[0-9]+$' | sort -n | head -n1)"
if [[ -z "$CANON" ]]; then
  err "no comment available to write to (a create may have landed but was not re-found) - treat the lane as UNREPORTED and carry that forward to the next cycle"
  exit 12
fi

if ! gh api --method PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$BODY_FILE" >/dev/null 2>&1; then
  err "the PATCH of comment $CANON failed - treat the lane as UNREPORTED and carry that forward to the next cycle; the comment holds an earlier body, not this cycle's write"
  exit 13
fi

# --- Post-write read-back ----------------------------------------------------
verify() {
  local back
  back="$(gh api "repos/$REPO/issues/comments/$1" 2>/dev/null | jq -r '.body // empty' 2>/dev/null | tr -d '\r')" || return 1
  sentinel_ok "$back"
}

if ! verify "$CANON"; then
  err "comment $CANON does NOT carry a well-formed telemetry body after the write - treat the lane as UNREPORTED and carry that forward to the next cycle; do not trust the timestamp"
  exit 14
fi

# --- Duplicate supersede (only after a verified canonical write) -------------
# `-f body=` here, not `-F body=@`: the tombstone is a literal string, not a file.
for dup in $(printf '%s\n' "$LIST" | grep -E '^[0-9]+$' | sort -n | tail -n +2); do
  gh api --method PATCH "repos/$REPO/issues/comments/$dup" \
    -f body="Superseded duplicate - canonical telemetry comment: $CANON" >/dev/null 2>&1 || true
done

printf 'telemetry: upserted comment %s (marker=%s) on %s#%s\n' "$CANON" "$MARKER" "$REPO" "$ISSUE"
exit 0
