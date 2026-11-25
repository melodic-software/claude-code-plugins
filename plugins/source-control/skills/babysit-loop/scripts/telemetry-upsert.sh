#!/usr/bin/env bash
set -uo pipefail
unset CDPATH

die() {
  local code="$1"
  shift
  printf 'telemetry: %s\n' "$*" >&2
  exit "$code"
}

REPO="" ISSUE="" INSTANCE="" BODY_FILE="" BODY_DIR="" APP_SLUG="" READ=""
while (($#)); do
  if [[ "$1" == --read ]]; then
    READ=1
    shift
    continue
  fi
  [[ "$1" == --repo || "$1" == --issue || "$1" == --instance || "$1" == --body-file || "$1" == --body-dir || "$1" == --app-slug ]] ||
    die 3 "unknown argument: $1"
  (($# >= 2)) || die 3 "$1 requires a value"
  case "$1" in
    --repo) REPO="$2" ;;
    --issue) ISSUE="$2" ;;
    --instance) INSTANCE="$2" ;;
    --app-slug) APP_SLUG="$2" ;;
    --body-dir) BODY_DIR="$2" ;;
    *) BODY_FILE="$2" ;;
  esac
  shift 2
done

type -P gh >/dev/null 2>&1 || die 4 "gh not found; nothing written"

[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ && ! "/$REPO/" =~ /\.+/ ]] ||
  die 3 "--repo must be owner/repo (got '$REPO'); nothing written"
[[ "$ISSUE" =~ ^[1-9][0-9]*$ ]] || die 3 "--issue must be a positive integer (got '$ISSUE'); nothing written"
[[ "$APP_SLUG" == "\${"* ]] && APP_SLUG=""
[[ -z "$APP_SLUG" || "$APP_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
  die 3 "--app-slug must be a GitHub App slug (got '$APP_SLUG'); nothing written"

# shellcheck source=telemetry-body-gate.sh
. "${BASH_SOURCE[0]%/*}/telemetry-body-gate.sh"
SAFE_OK=""
SAFE_WHY=""
if tbg_safe_dir source-control "$BODY_DIR"; then SAFE_OK=1; else SAFE_WHY="$TBG_ERR"; fi

if [[ -z "$INSTANCE" || "$INSTANCE" == "\${"* ]]; then
  [[ -n "$SAFE_OK" ]] || die 3 "lane_instance unset and $SAFE_WHY; nothing read or written"
  tbg_instance || die 3 "$TBG_ERR; nothing read or written"
  INSTANCE="$TBG_INSTANCE"
  printf "telemetry: lane_instance unset; using the stored random id '%s'\n" "$INSTANCE" >&2
fi
[[ "$INSTANCE" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] ||
  die 3 "lane_instance '$INSTANCE' is not ^[a-z0-9][a-z0-9-]{0,31}\$; refusing to build a marker"
type -P node >/dev/null 2>&1 || die 4 "node not found (the leak scan needs it); nothing read or written"
tbg_check_instance "${BASH_SOURCE[0]%/*}/../../../lib/publish-gate.mjs" "$INSTANCE" ||
  die 3 "$TBG_ERR; nothing read or written"

SENT="<!-- harness-ops:lane-telemetry marker=source-control:babysit-loop@$INSTANCE -->"

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

ids() { printf '%s\n' "$1" | grep -E '^[0-9]+$' | sort -n; }
canonical() { ids "$1" | head -n1; }

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

[[ -n "$SAFE_OK" ]] || die 3 "$SAFE_WHY; nothing read or written"
SEND_FILE=""
BODY_COPY=""
trap 'rm -f "$BODY_COPY" "$SEND_FILE"' EXIT
tbg_read_body "$BODY_FILE" || die 3 "$TBG_ERR; nothing read or written"
BODY_COPY="$TBG_COPY"
body="$(tr -d '\r' <"$BODY_COPY")"
[[ -n "$body" && "$body" != @* ]] ||
  die 3 "body is empty or a literal @path - nothing written; fix the body composition, do not re-run blind"
[[ "${body%%$'\n'*}" == "$SENT" ]] && body="${body#*$'\n'}"
[[ "$body" == "$SENT" ]] && body=""
(($(printf '%s' "$body" | wc -c) >= 16)) ||
  die 3 "body carries under 16 payload bytes below the sentinel - nothing written; fix the body composition, do not re-run blind"
SENT_BODY="$SENT"$'\n'"$body"

leak="$(printf '%s\n' "$SENT_BODY" | tbg_scan "${BASH_SOURCE[0]%/*}/../../../lib/publish-gate.mjs")" ||
  die 3 "the leak scan could not run; nothing written"
[[ -z "$leak" ]] ||
  die 3 "body withheld: $leak; nothing written"

SEND_FILE="$(mktemp)" || die 3 "cannot create a temporary file; nothing written"
printf '%s\n' "$SENT_BODY" >"$SEND_FILE"

need_identity

LIST="$(lookup)" || die 5 "comment lookup failed; nothing written this cycle (fail closed)"
if [[ -z "$LIST" ]]; then
  POSTED="$(gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$SEND_FILE" \
    --jq '(.id | tostring) + " " + .user.login')" ||
    die 5 "creating the telemetry comment failed; nothing written"
  POSTED_ID="${POSTED%% *}" POSTED_AS="${POSTED#* }"
  if [[ "$POSTED_AS" != "$ME" ]]; then
    if [[ "$POSTED_ID" =~ ^[0-9]+$ ]] && gh api -X DELETE "repos/$REPO/issues/comments/$POSTED_ID" >/dev/null; then
      cleanup="deleted it"
    else
      cleanup="deleting comment $POSTED_ID failed; remove it by hand"
    fi
    die 5 "the comment was posted as '$POSTED_AS', not the resolved write identity '$ME' ($cleanup); set --app-slug to match '$POSTED_AS' before the next cycle"
  fi
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

for DUP in $(ids "$LIST" | tail -n +2); do
  gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
    -f body="Superseded duplicate - canonical telemetry comment: $CANON" >/dev/null ||
    printf 'telemetry: tombstoning duplicate comment %s failed; the next cycle retries it\n' "$DUP" >&2
done
printf 'telemetry: comment %s verified (marker=source-control:babysit-loop@%s)\n' "$CANON" "$INSTANCE"
