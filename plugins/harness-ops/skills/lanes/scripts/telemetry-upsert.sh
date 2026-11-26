#!/usr/bin/env bash
# Exit codes:
#   0  upserted and verified (or, with --dry-run, resolved)
#   3  invalid argument (bad issue/marker/repo, body-file outside the safe dir),
#      or a body that failed the pre-write gate (over the size cap, under the
#      size floor, starting with a literal `@`, or matching the leak scan, which
#      names the rule and never the match), or a --marker findMachine matches
#      (a hostname the public sentinel would publish) — NOTHING was written
#   4  prerequisite missing (gh, jq or node), or the repo / safe body dir / write
#      identity unresolved (nothing was written)
#   5  a gh API call (list / create / update) failed, the comment list was empty
#      or not a JSON array of objects, or detection could not read it (nothing
#      was written)
#   6  the write went through but its read-back did not verify (or could not be
#      performed) — the comment on the issue is NOT confirmed telemetry

set -uo pipefail
unset CDPATH

jq() { command jq "$@" | tr -d '\r'; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
usage() {
  cat <<'EOF'
telemetry-upsert.sh: maintain exactly ONE marker-identified comment on a tracking issue,
editing it in place every cycle. The comment's first line is the sentinel
`<!-- harness-ops:lane-telemetry marker=<MARKER> -->`; only the write identity's comments
are matched, and a `<lane>@<instance>` marker names one writer.

Usage:
  telemetry-upsert.sh --issue N --marker STR --body-file PATH
                      [--body-dir DIR] [--repo owner/name] [--app-slug SLUG]
                      [--dry-run]

  --issue N          tracking issue number (required)
  --marker STR       marker id, [A-Za-z0-9:@._-]+ (required)
  --body-file PATH   comment body below the sentinel (required; `-` reads stdin; cap 64 KiB);
                     a real path must resolve under the safe body dir
  --body-dir DIR     safe body dir (default: $CLAUDE_PLUGIN_DATA); its last segment must name
                     harness-ops, and it is never /, the home dir, or an ancestor of it
  --repo owner/name  target repo (default: `gh repo view` for the cwd's repo)
  --app-slug SLUG    GitHub App whose installation token gh runs under ([a-z0-9][a-z0-9-]*)
  --dry-run          resolve and report the action; write nothing
  --help

Exit codes:
  0  upserted and verified (or, with --dry-run, resolved)
  3  invalid argument, or a body that failed the pre-write gate (over the size cap, under
     the size floor, starting with a literal `@`, or matching the leak scan), or a marker
     findMachine matches; nothing was written
  4  prerequisite missing (gh, jq or node), or the repo / safe body dir / write identity
     unresolved; nothing was written
  5  a gh API call failed, or the comment list was unreadable; nothing was written
  6  the write went through but its read-back did not verify (or could not run)
EOF
}

MAX_BODY_BYTES=65536
MIN_BODY_BYTES=16

require_value() {
  (($# >= 2)) && return 0
  err "$1 requires a value"
  exit 3
}

ISSUE=""
MARKER=""
BODY_FILE=""
BODY_DIR=""
REPO=""
APP_SLUG=""
DRY_RUN=0
set_opt() {
  case "$1" in
  --issue) ISSUE="$2" ;;
  --marker) MARKER="$2" ;;
  --body-file) BODY_FILE="$2" ;;
  --body-dir) BODY_DIR="$2" ;;
  --repo) REPO="$2" ;;
  *) APP_SLUG="$2" ;;
  esac
}
while (($#)); do
  case "$1" in
  --issue | --marker | --body-file | --body-dir | --repo | --app-slug)
    require_value "$@"
    set_opt "$1" "$2"
    shift 2
    ;;
  --issue=* | --marker=* | --body-file=* | --body-dir=* | --repo=* | --app-slug=*)
    set_opt "${1%%=*}" "${1#*=}"
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
    err "unknown argument: $1 (see --help)"
    exit 3
    ;;
  esac
done

for bin in gh jq node; do
  type -P "$bin" >/dev/null 2>&1 || {
    err "$bin not found (required)"
    exit 4
  }
done

[[ "$ISSUE" =~ ^[0-9]+$ ]] || {
  err "--issue must be a positive integer (got: '${ISSUE:-}')"
  exit 3
}
[[ "$MARKER" =~ ^[A-Za-z0-9:@._-]+$ ]] || {
  err "--marker must match [A-Za-z0-9:@._-]+ (got: '${MARKER:-}')"
  exit 3
}
[[ -n "$BODY_FILE" ]] || {
  err "--body-file is required"
  exit 3
}
[[ "$APP_SLUG" == "\${user_config."* ]] && APP_SLUG=""
if [[ -n "$APP_SLUG" && ! "$APP_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  err "--app-slug must be a GitHub App slug, got: $APP_SLUG"
  exit 3
fi

# shellcheck source=lib/telemetry-body-gate.sh
. "${BASH_SOURCE[0]%/*}/lib/telemetry-body-gate.sh"
if [[ "$BODY_FILE" == "-" ]]; then
  body_text="$(cat)"
else
  [[ -e "$BODY_FILE" || -L "$BODY_FILE" ]] || {
    err "body file not found; nothing was written"
    exit 3
  }
  tbg_safe_dir harness-ops "$BODY_DIR" || {
    err "$TBG_ERR (or pipe the body via --body-file -)"
    exit 4
  }
  tbg_read_body "$BODY_FILE" || {
    err "$TBG_ERR; nothing was read or written"
    exit 3
  }
  body_text="$(cat -- "$TBG_COPY")"
  rm -f -- "$TBG_COPY"
fi

body_bytes="$(printf '%s' "$body_text" | wc -c | tr -d ' ')"
if ((body_bytes > MAX_BODY_BYTES)); then
  err "body is ${body_bytes} bytes, over the ${MAX_BODY_BYTES}-byte cap — telemetry bodies are small"
  exit 3
fi
if [[ "$body_text" == @* ]]; then
  err "body starts with a literal '@' — a body argument was given an @path instead of the file's contents (use --body-file PATH, or pipe the body via --body-file -)"
  err "nothing was written: fix the caller's body, do not re-run blind"
  exit 3
fi
if ((body_bytes < MIN_BODY_BYTES)); then
  err "body is ${body_bytes} bytes, under the ${MIN_BODY_BYTES}-byte floor — a comment that would look fresh but hold no telemetry"
  err "nothing was written: fix the caller's body, do not re-run blind"
  exit 3
fi

tbg_check_instance "${BASH_SOURCE[0]%/*}/../../../lib/publish-gate.mjs" "$MARKER" || {
  err "$TBG_ERR; nothing was written"
  exit 3
}
SENTINEL="<!-- harness-ops:lane-telemetry marker=$MARKER -->"
new_body="$SENTINEL"$'\n'"$body_text"

leak="$(printf '%s' "$new_body" | tbg_scan "${BASH_SOURCE[0]%/*}/../../../lib/publish-gate.mjs")" || {
  err "the leak scan could not run; nothing was written"
  exit 3
}
if [[ -n "$leak" ]]; then
  err "body withheld: $leak; nothing was written"
  exit 3
fi

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null | tr -d '\r')"
  [[ -n "$REPO" ]] || {
    err "could not resolve repo (run inside a gh repo or pass --repo owner/name)"
    exit 4
  }
fi

[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || {
  err "--repo must be owner/repo (got: '$REPO')"
  exit 3
}

WRITE_IDENTITY=""
installation_token() { gh api 'installation/repositories?per_page=1' >/dev/null 2>&1; }
resolve_write_identity() {
  local who="" user_ok=1
  who="$(gh api user --jq '.login + " " + .type' 2>/dev/null | tr -d '\r')" || user_ok=0
  if ((user_ok)) && [[ "$who" == *" User" ]]; then
    WRITE_IDENTITY="${who% User}"
  elif [[ -n "$APP_SLUG" ]] && { ((user_ok)) || installation_token; }; then
    WRITE_IDENTITY="${APP_SLUG}[bot]"
  elif [[ "$who" == *" Bot" ]]; then
    WRITE_IDENTITY="${who% Bot}"
    [[ "$WRITE_IDENTITY" == *"[bot]" ]] || WRITE_IDENTITY+="[bot]"
  else
    return 1
  fi
  [[ "$WRITE_IDENTITY" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*(\[bot\])?$ ]]
}

resolve_write_identity || {
  err "cannot resolve the lanes' write identity (gh api user failed or reported no User, and the token is not an App installation token); pass --app-slug under an App token. Nothing was written."
  exit 4
}

raw_pages="$(gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" 2>/dev/null)" || {
  err "failed to list comments on $REPO#$ISSUE (gh api)"
  exit 5
}
comments="$(jq -se '
  if length > 0 and all(.[]; type == "array") then add else error("not an array") end
  | if all(.[]; type == "object") then . else error("not an object") end
' <<<"$raw_pages" 2>/dev/null)" || {
  err "comment list on $REPO#$ISSUE did not parse as a JSON array of comment objects. Nothing was written."
  exit 5
}
detect_failed() {
  err "could not read the comment list on $REPO#$ISSUE (detection jq failed). Nothing was written."
  exit 5
}

target_id="$(jq -r --arg s "$SENTINEL" --arg me "$WRITE_IDENTITY" '
  [ .[] | select((.user.login // "") == $me and (.body // "" | contains($s))) ]
  | sort_by(.created_at) | last | .id // empty
' <<<"$comments")" || detect_failed
detect="sentinel"

if [[ -z "$target_id" ]]; then
  target_id="$(jq -r --arg m "$MARKER" --arg me "$WRITE_IDENTITY" '
    ($m | gsub("[.]"; "\\.")) as $mre
    | [ .[]
        | select((.user.login // "") == $me
            and ((.body // "") | test("(?<![A-Za-z0-9:@._-])" + $mre + "(?![A-Za-z0-9:@._-])"))) ]
    | sort_by(.created_at) | last | .id // empty
  ' <<<"$comments")" || detect_failed
  [[ -n "$target_id" ]] && detect="marker-fallback"
fi

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

verify_fail() {
  err "post-write read-back FAILED for $REPO#$ISSUE (marker=$MARKER): $1"
  [[ -n "$html_url" ]] && err "the written comment is at $html_url"
  err "${2:-telemetry for this cycle is NOT trustworthy — inspect the comment, do not re-run blind}"
  exit 6
}
unconfirmed="the body cleared the pre-write gate, so the comment is probably intact — but this cycle is UNCONFIRMED, not proven good"

new_id="${new_id:-$target_id}"
[[ -n "$new_id" ]] || verify_fail "the ${action} response carried no comment id, so the write cannot be read back" "$unconfirmed"

[[ "$new_id" =~ ^[0-9]+$ ]] ||
  verify_fail "the ${action} response carried a non-numeric comment id ('$new_id'), so the write cannot be read back" "$unconfirmed"

verify_err="$(mktemp 2>/dev/null)" || verify_err=""
if [[ -n "$verify_err" ]]; then
  trap 'rm -f "$verify_err"' EXIT
  trap 'rm -f "$verify_err"; exit 130' INT TERM
fi
verify_body=""
verify_read=0
# One retry covers a network blip only; a secondary rate limit needs a wait of at least a minute.
# https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
for verify_attempt in 1 2; do
  if verify_body="$(gh api "repos/$REPO/issues/comments/$new_id" --jq '.body' 2>"${verify_err:-/dev/null}" | tr -d '\r')"; then
    verify_read=1
    break
  fi
  ((verify_attempt == 1)) && sleep 2
done
if ((verify_read == 0)); then
  verify_err_text=""
  [[ -n "$verify_err" ]] && verify_err_text="$(tr -d '\r' <"$verify_err" | tr '\n' ' ')"
  verify_err_text="${verify_err_text:0:500}"
  case "$verify_err_text" in
  *"HTTP 404"*)
    verify_verdict="comment $new_id is NOT RETRIEVABLE (404) — it was deleted, its issue was, or this token can no longer read it; do not read this as 'probably intact'"
    ;;
  *) verify_verdict="$unconfirmed" ;;
  esac
  verify_fail "could not re-read comment $new_id after 2 attempts (gh api GET): ${verify_err_text:-no error text captured}" "$verify_verdict"
fi

[[ "$verify_body" == *"$SENTINEL"* ]] ||
  verify_fail "comment $new_id does not carry the marker sentinel after the write"

verify_rest="${verify_body#*"$SENTINEL"}"
verify_rest="${verify_rest#$'\n'}"

[[ "$verify_rest" == @* ]] &&
  verify_fail "comment $new_id starts with a literal '@' below the sentinel, but the body sent did not — the stored comment diverged from what was written"

verify_bytes="$(printf '%s' "$verify_rest" | wc -c | tr -d ' ')"
((verify_bytes >= MIN_BODY_BYTES)) ||
  verify_fail "comment $new_id carries ${verify_bytes} bytes below the sentinel, under the ${MIN_BODY_BYTES}-byte floor — a comment that looks fresh but holds no telemetry"

printf 'telemetry-upsert: %sd comment %s (marker=%s) on %s#%s\n' \
  "$action" "$new_id" "$MARKER" "$REPO" "$ISSUE"
[[ -n "$html_url" ]] && printf '%s\n' "$html_url"
exit 0
