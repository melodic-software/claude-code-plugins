#!/usr/bin/env bash
# telemetry-upsert.sh — maintain this babysit-loop instance's ONE sentinel-identified
# telemetry comment on the lane's tracking issue, and confirm the write landed.
#
# Usage:
#   telemetry-upsert.sh --repo OWNER/REPO --issue N --instance ID --body-file PATH --body-dir DIR [--app-slug SLUG]
#   telemetry-upsert.sh --repo OWNER/REPO --issue N --instance ID --read [--body-dir DIR] [--app-slug SLUG]
#
#   --read          print this identity's canonical comment body (empty when it has
#                   none) and write nothing; the re-anchor read of the state block.
#   --app-slug SLUG the GitHub App whose installation token gh runs under; its
#                   writes land as SLUG[bot]. Empty, or a literal unsubstituted
#                   ${user_config.…} placeholder, counts as absent.
#
# Only comments written by this script's own write identity count, whoever else
# posts the public sentinel. The identity is the `gh api user` login when that call
# reports a User; when it fails (an App installation token cannot call it) or
# reports a Bot, it is SLUG[bot] from --app-slug, else the reported Bot login with
# its [bot] suffix. Unresolved: exit 5, nothing read or written.
#
#   --instance ID   lane instance id, ^[a-z0-9][a-z0-9-]{0,31}$. Empty, or a literal
#                   unsubstituted ${user_config.…} placeholder, falls back to a random
#                   `lane-<hex>` id made once and kept in DIR/lane-instance, so it is
#                   stable across restarts without publishing the hostname in the
#                   public marker; the fallback is logged and passes the same check.
#   --body-file PATH  this cycle's telemetry (report + state block). The script
#                   writes the sentinel line above it; a file that already opens with
#                   this instance's sentinel is sent as-is.
#   --body-dir DIR  directory the body file must resolve under (default: an
#                   inherited CLAUDE_PLUGIN_DATA). Either counts only when its last
#                   path segment names source-control, and never when it is /, the
#                   home dir, or an ancestor of it. SECURITY: lane prompts drive this script,
#                   and an unconstrained path would let a prompt-injected
#                   `--body-file ~/.ssh/id_rsa` be posted as a public comment. A
#                   symlink leaf or a path resolving outside DIR is refused before any
#                   read; the body is then scanned with scanLeak and withheld whole on
#                   any hit, naming the rule and never the match.
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
#   3  invalid input, a body file outside the safe body dir or a symlink, or a
#      body that failed the pre-write gate or the leak scan, or a lane instance
#      findMachine matches (a hostname the public marker would publish) — nothing
#      written
#   4  gh or node not found — nothing written
#   5  a gh call failed before anything verifiable landed: the write identity or
#      the lookup (nothing written), the POST, or the PATCH (the comment holds an
#      earlier body), or the POST landed under another login (a wrong
#      --app-slug; that comment is deleted); under --read, the identity,
#      lookup, or read failed
#   6  the write was sent but is unconfirmed: the created comment was not re-found,
#      the read-back failed, or what was stored differs from what was sent
# A failed duplicate tombstone after a verified write is reported on stderr only;
# the next cycle retries it.

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

# telemetry-body-gate.sh (a generated copy of lib/telemetry-body-gate.sh) holds
# the rule every lane telemetry upsert shares. The safe body dir must be this
# plugin's data dir (its last segment names source-control; never /, the home
# dir or an ancestor of it); --read needs it only for the instance fallback.
# shellcheck source=telemetry-body-gate.sh
. "${BASH_SOURCE[0]%/*}/telemetry-body-gate.sh"
SAFE_OK=""
SAFE_WHY=""
if tbg_safe_dir source-control "$BODY_DIR"; then SAFE_OK=1; else SAFE_WHY="$TBG_ERR"; fi

# A random id, made once and kept in the safe body dir: stable across restarts,
# distinct per machine, and never the hostname, which the public marker would publish.
if [[ -z "$INSTANCE" || "$INSTANCE" == "\${"* ]]; then
  [[ -n "$SAFE_OK" ]] || die 3 "lane_instance unset and $SAFE_WHY; nothing read or written"
  tbg_instance || die 3 "$TBG_ERR; nothing read or written"
  INSTANCE="$TBG_INSTANCE"
  printf "telemetry: lane_instance unset; using the stored random id '%s'\n" "$INSTANCE" >&2
fi
# Rejected, never trimmed into something that looks valid.
[[ "$INSTANCE" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] ||
  die 3 "lane_instance '$INSTANCE' is not ^[a-z0-9][a-z0-9-]{0,31}\$; refusing to build a marker"
type -P node >/dev/null 2>&1 || die 4 "node not found (the leak scan needs it); nothing read or written"
tbg_check_instance "${BASH_SOURCE[0]%/*}/../../../lib/publish-gate.mjs" "$INSTANCE" ||
  die 3 "$TBG_ERR; nothing read or written"

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

# --- Body-file containment ---------------------------------------------------
# The file must resolve under the safe body dir, and is read once into a private
# copy every later step uses; see telemetry-body-gate.sh.
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

# --- Leak scan ---------------------------------------------------------------
# The comment is public. scanLeak and findMachine (this plugin's generated copy of
# lib/publish-gate.mjs) judge what would be posted; a hit withholds all of it,
# never a masked copy, and the message names only the rule. A plain assignment,
# a home path or a private hostname is withheld too, and so is a scan that cannot run.
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
  # A wrong --app-slug would otherwise leave a never-found comment behind every
  # cycle; the token that posted it can delete it.
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

for DUP in $(printf '%s\n' "$LIST" | grep -E '^[0-9]+$' | sort -n | tail -n +2); do
  gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
    -f body="Superseded duplicate - canonical telemetry comment: $CANON" >/dev/null ||
    printf 'telemetry: tombstoning duplicate comment %s failed; the next cycle retries it\n' "$DUP" >&2
done
printf 'telemetry: comment %s verified (marker=source-control:babysit-loop@%s)\n' "$CANON" "$INSTANCE"
