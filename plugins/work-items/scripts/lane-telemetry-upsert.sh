#!/usr/bin/env bash
set -uo pipefail
unset CDPATH

MIN_PAYLOAD_BYTES=16

err() { printf 'telemetry: %s\n' "$*" >&2; }
usage() {
  cat <<'TXT'
Maintain one sentinel-identified telemetry comment per lane instance on a lane's tracking issue, edited in place each cycle.

Usage: lane-telemetry-upsert.sh --lane work-loop|attend-queue --instance <id> --repo <owner/name> --issue <n> --body-file <path> --body-dir <dir> [--app-slug <slug>]
  --lane       lane type: work-loop or attend-queue
  --instance   lane-instance id, ^[a-z0-9][a-z0-9-]{0,31}$; empty falls back to a stored random id
  --repo       target repository, owner/name
  --issue      tracking issue number
  --body-file  the comment body; its first line is the sentinel, with at least 16 payload bytes below
  --body-dir   directory the body file must resolve under (default: an inherited CLAUDE_PLUGIN_DATA)
  --app-slug   the GitHub App whose installation token gh runs under
  --help       print this help

Exit codes: 0 upserted and verified; 2 usage; 3 bad --lane; 4 malformed lane instance; 5 lane instance over 32 characters;
6 bad --repo; 7 bad --issue; 8 gh, jq or node not on PATH; 9 body file missing, empty or opens with @;
10 body not sentinel-prefixed or under 16 payload bytes; 11 comment lookup failed; 12 no comment to write to;
13 the PATCH failed; 14 read-back does not hold this cycle's body; 15 write identity unresolved or wrong;
16 no safe body dir, or the body file is a symlink or outside it; 17 body matches the leak scan;
18 lane instance matches a private hostname. Exits 9, 10, 15, 16, 17 and 18 write nothing.
TXT
}

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
BODY_DIR=""
APP_SLUG=""
while (($#)); do
  case "$1" in
  --lane=* | --instance=* | --repo=* | --issue=* | --body-file=* | --body-dir=* | --app-slug=*)
    set -- "${1%%=*}" "${1#*=}" "${@:2}"
    ;;
  --lane | --instance | --repo | --issue | --body-file | --body-dir | --app-slug)
    require_value "$@"
    var="${1#--}"
    var="${var//-/_}"
    printf -v "${var^^}" '%s' "$2"
    shift 2
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

# shellcheck disable=SC2016  # the placeholder is matched literally, never expanded
[[ "$INSTANCE" != '${user_config.'* ]] || INSTANCE=""
# shellcheck disable=SC2016  # the placeholder is matched literally, never expanded
[[ "$APP_SLUG" != '${user_config.'* ]] || APP_SLUG=""

for bin in gh jq node; do
  command -v "$bin" >/dev/null 2>&1 || {
    err "$bin not found (required)"
    exit 8
  }
done

# shellcheck source=telemetry-body-gate.sh
. "${BASH_SOURCE[0]%/*}/telemetry-body-gate.sh"
if ! tbg_safe_dir work-items "$BODY_DIR"; then
  err "$TBG_ERR - nothing read or written"
  exit 16
fi
tbg_read_body "$BODY_FILE"
case $? in
0) : ;;
2)
  err "body is missing or empty - nothing written; fix the body composition, do not re-run blind"
  exit 9
  ;;
*)
  err "$TBG_ERR - nothing read or written"
  exit 16
  ;;
esac
BODY_FILE="$TBG_COPY"
trap 'rm -f "$BODY_FILE"' EXIT

if [[ -z "$INSTANCE" ]]; then
  if ! tbg_instance; then
    err "$TBG_ERR - nothing written"
    exit 4
  fi
  INSTANCE="$TBG_INSTANCE"
  err "no lane instance supplied; using the stored random id '$INSTANCE'"
fi

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
if ! tbg_check_instance "${BASH_SOURCE[0]%/*}/../lib/publish-gate.mjs" "$INSTANCE"; then
  err "$TBG_ERR - nothing written"
  exit 18
fi

if [[ ! "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ || "/$REPO/" =~ /\.+/ ]]; then
  err "--repo must be owner/name (got: '$REPO')"
  exit 6
fi
if [[ ! "$ISSUE" =~ ^[0-9]+$ ]]; then
  err "--issue must be a positive integer (got: '$ISSUE')"
  exit 7
fi

MARKER="work-items:$LANE@$INSTANCE"
SENT="<!-- harness-ops:lane-telemetry marker=$MARKER -->"

if [[ ! -s "$BODY_FILE" ]]; then
  err "body is missing or empty - nothing written; fix the body composition, do not re-run blind"
  exit 9
fi
if [[ "$(head -c 1 "$BODY_FILE")" == "@" ]]; then
  err "body is a literal @path - nothing written; fix the body composition, do not re-run blind"
  exit 9
fi

BODY_TEXT="$(<"$BODY_FILE")"

sentinel_ok() {
  local text="$1" payload_bytes
  [[ "$text" == "$SENT"* ]] || return 1
  payload_bytes="$(printf '%s' "$text" | tail -n +2 | wc -c | tr -d ' ')"
  ((payload_bytes >= MIN_PAYLOAD_BYTES))
}

if ! sentinel_ok "$BODY_TEXT"; then
  err "body is not sentinel-prefixed or carries no payload - nothing written; fix the body composition, do not re-run blind"
  exit 10
fi

if ! leak="$(tbg_scan "${BASH_SOURCE[0]%/*}/../lib/publish-gate.mjs" <"$BODY_FILE")"; then
  err "the leak scan could not run - nothing written"
  exit 17
fi
if [[ -n "$leak" ]]; then
  err "body withheld: $leak - nothing written"
  exit 17
fi

if [[ -n "$APP_SLUG" && ! "$APP_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  err "--app-slug must be a GitHub App slug (got: '$APP_SLUG') - nothing written; treat the lane as UNREPORTED"
  exit 15
fi
WRITER=""
if who="$(gh api user --jq '.login + " " + .type' 2>/dev/null)" && [[ "$who" == *" User" ]]; then
  WRITER="${who% User}"
elif [[ -n "$APP_SLUG" ]]; then
  WRITER="${APP_SLUG}[bot]"
elif [[ "${who:-}" == *" Bot" ]]; then
  WRITER="${who% Bot}"
  [[ "$WRITER" == *"[bot]" ]] || WRITER="${WRITER}[bot]"
fi
if [[ ! "$WRITER" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*(\[bot\])?$ ]]; then
  err "cannot resolve the write identity ('$WRITER'); under an App token pass --app-slug - nothing written; treat the lane as UNREPORTED"
  exit 15
fi

lookup() {
  local pages ids
  pages="$(gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" 2>/dev/null)" || return 1
  ids="$(jq -r --arg s "$SENT" --arg w "$WRITER" \
    '.[] | select(((.body // "") | startswith($s)) and (.user.login == $w)) | .id' <<<"$pages" 2>/dev/null)" || return 1
  printf '%s\n' "$ids"
}

if ! LIST="$(lookup)"; then
  err "comment lookup failed; skipping upsert this cycle (fail closed)"
  exit 11
fi

if [[ -z "${LIST//[[:space:]]/}" ]]; then
  POSTED_AS="$(gh api --method POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE" --jq '.user.login' 2>/dev/null)" || POSTED_AS=""
  if [[ -n "$POSTED_AS" && "$POSTED_AS" != "$WRITER" ]]; then
    err "the comment was posted as '$POSTED_AS', not the resolved write identity '$WRITER'; fix --app-slug before the next cycle - treat the lane as UNREPORTED"
    exit 15
  fi
  LIST="$(lookup)" || LIST=""
fi

SORTED="$(printf '%s\n' "$LIST" | grep -E '^[0-9]+$' | sort -n)"
mapfile -t IDS <<<"$SORTED"
CANON="${IDS[0]:-}"
if [[ -z "$CANON" ]]; then
  err "no comment available to write to (a create may have landed but was not re-found) - treat the lane as UNREPORTED and carry that forward to the next cycle"
  exit 12
fi

if ! gh api --method PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$BODY_FILE" >/dev/null 2>&1; then
  err "the PATCH of comment $CANON failed - treat the lane as UNREPORTED and carry that forward to the next cycle; the comment holds an earlier body, not this cycle's write"
  exit 13
fi

verify() {
  local back want
  back="$(gh api "repos/$REPO/issues/comments/$1" 2>/dev/null | jq -r '.body // empty' 2>/dev/null | tr -d '\r')" || return 1
  want="$(tr -d '\r' <"$BODY_FILE")"
  [[ "$back" == "$want" ]]
}

if ! verify "$CANON"; then
  err "comment $CANON does NOT hold this cycle's body after the write - treat the lane as UNREPORTED and carry that forward to the next cycle; do not trust the timestamp"
  exit 14
fi

for dup in "${IDS[@]:1}"; do
  gh api --method PATCH "repos/$REPO/issues/comments/$dup" \
    -f body="Superseded duplicate - canonical telemetry comment: $CANON" >/dev/null 2>&1 || true
done

printf 'telemetry: upserted comment %s (marker=%s) on %s#%s\n' "$CANON" "$MARKER" "$REPO" "$ISSUE"
exit 0
