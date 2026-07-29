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
# PRE-WRITE BODY VALIDATION (#952, guarding the #943 fail-open) — the real gate:
#   Before anything is sent, the caller's body is asserted to not begin with a
#   literal `@` and to clear MIN_BODY_BYTES. A failure exits 3 having made zero
#   API calls, so the degraded body never reaches the tracking issue — there is
#   no public comment to retract and no window in which a reader sees it.
#
#   The `@` assertion is the specific defect this guards (see the lanes SKILL.md
#   section "Never pass a body as an `@path` string" for the caller-facing rule):
#   a body argument given an `@path` string posts the literal path text, and the
#   comment's timestamp still moves — so the telemetry surface looks FRESH while
#   carrying no data, an observability fail-open a timestamp check cannot see.
#   The length floor catches the degenerate sibling: a sentinel-only comment
#   from an empty body.
#
#   This script cannot commit the `@path` mistake through its own plumbing (it
#   reads the body into a shell variable before any gh call, so `-f body=` never
#   sees an `@path`). The gate is here for the body TEXT a caller hands it: a
#   lane that composed `@/tmp/telemetry.txt` as its body content, meaning the
#   file, arrives at this script as that literal string.
#
#   Validation is unconditional and has no opt-out flag: this script is driven by
#   AI lane prompts, and a `--no-verify` escape hatch would be reachable by the
#   same prompt-injected caller the check exists to catch.
#
# POST-WRITE READ-BACK (secondary confirmation, not the gate):
#   After the create/update, the comment is re-read via a separate GET and the
#   same assertions re-run against what a reader of the issue will actually find,
#   plus the sentinel. A body that fails exits 6 with the comment id/url named.
#
#   Scope it honestly. The pre-write gate already proved the body we SENT is
#   sound, and the GET targets the id we just wrote, so this pass sees only what
#   happened to THAT comment after the write returned: a truncated or mangled
#   store, a concurrent writer overwriting or stripping the sentinel, or the
#   comment being deleted out from under us (404). It cannot tell that detection
#   resolved the WRONG comment — we would have stamped our sentinel and body onto
#   it, and reading that id back finds exactly what we expect. (Nor is it the
#   guard for editing another user's comment: that PATCH 403s and exits 5.)
#
#   The GET is retried once: the write has already landed by then, so a momentary
#   read failure must not report a good cycle as a bad one. That retry is a
#   network-blip guard only — it does not wait out a secondary rate limit. A
#   second failure is still fail-closed — the cycle is reported UNCONFIRMED
#   rather than good — but its message says so, because a check that could not
#   run is not a check that disagreed, and it branches on gh's own error: a 404
#   means the comment is gone, not merely unread.
#
# Output (stdout): one action line, e.g.
#   telemetry-upsert: updated comment 12345 (marker=lane:triage) on <owner/repo>#<issue>
#   <html_url>
#
# Exit codes:
#   0  upserted and verified (or, with --dry-run, resolved)
#   3  invalid argument (bad issue/marker/repo, body-file outside the safe dir),
#      or a body that failed the pre-write gate (over the size cap, under the
#      size floor, or starting with a literal `@`) — NOTHING was written
#   4  prerequisite missing (gh or jq), or the repo / safe body dir unresolved
#   5  a gh API call (list / create / update) failed
#   6  the write went through but its read-back did not verify (or could not be
#      performed) — the comment on the issue is NOT confirmed telemetry

set -uo pipefail

jq() { command jq "$@" | tr -d '\r'; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

for bin in gh jq; do
  type -P "$bin" >/dev/null 2>&1 || {
    err "$bin not found (required)"
    exit 4
  }
done

MAX_BODY_BYTES=65536 # 64 KiB — a telemetry body, not an essay
MIN_BODY_BYTES=16    # sanity floor for the body — below this is not telemetry

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

# --- Pre-write body gate -----------------------------------------------------
# All three checks run against the caller's body BEFORE any gh call, so a body
# that fails costs zero API calls and never lands on the tracking issue. The
# read-back below re-asserts the same properties on what came back; THIS is what
# keeps a degraded body from being published in the first place. Applied to file
# and stdin bodies alike.
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

# --- Post-write read-back (secondary confirmation) ---------------------------
# Re-READ the comment rather than trusting the create/update response echo: the
# echo proves the request was accepted, a GET proves what a reader of the issue
# will actually find. The body's CONTENT was already cleared by the pre-write
# gate, so what remains for this pass to catch is what happened to the comment
# AFTER the write returned — a mangled store, a concurrent overwrite, a deletion.
# It cannot detect that detection resolved the wrong comment; see the header.
#
# $2 overrides the remediation line, because "the check disagreed" and "the check
# could not run" call for opposite next steps.
verify_fail() {
  err "post-write read-back FAILED for $REPO#$ISSUE (marker=$MARKER): $1"
  [[ -n "$html_url" ]] && err "the written comment is at $html_url"
  err "${2:-telemetry for this cycle is NOT trustworthy — inspect the comment, do not re-run blind}"
  exit 6
}
unconfirmed="the body cleared the pre-write gate, so the comment is probably intact — but this cycle is UNCONFIRMED, not proven good"

# On the update path the id is already known — fall back to it rather than
# calling a successful PATCH unverifiable over a missing field in its response.
[[ -n "$new_id" ]] || new_id="${target_id:-}"
[[ -n "$new_id" ]] || verify_fail "the ${action} response carried no comment id, so the write cannot be read back" "$unconfirmed"

# Same rule the $REPO validation states above: nothing reaches a gh api URL path
# unvalidated. A GitHub comment id is an integer from either source, so this can
# only fire on a malformed response — but the rule does not carry an exception.
[[ "$new_id" =~ ^[0-9]+$ ]] ||
  verify_fail "the ${action} response carried a non-numeric comment id ('$new_id'), so the write cannot be read back" "$unconfirmed"

# The write has already landed by this point, so a momentary GET failure would
# otherwise report a good cycle as a bad one. Retry once before concluding the
# comment is unverifiable; a second failure is still fail-closed. The retry is a
# network-blip guard ONLY — it does not honor Retry-After, so a secondary rate
# limit (which outlasts it by far) reliably burns both attempts.
#
# gh's stderr is kept rather than discarded, and the verdict branches on it: a
# 404 means the comment is GONE, which contradicts the default "probably intact"
# reading, while a 403/429 means it is almost certainly still there and simply
# unread. The two call for opposite responses, so neither the raw message nor
# the conclusion drawn from it can be one-size-fits-all.
verify_err="$(mktemp)" || verify_fail "could not create a temp file to capture the read-back error" "$unconfirmed"
trap 'rm -f "$verify_err"' EXIT
verify_body=""
verify_read=0
for verify_attempt in 1 2; do
  if verify_body="$(gh api "repos/$REPO/issues/comments/$new_id" --jq '.body' 2>"$verify_err" | tr -d '\r')"; then
    verify_read=1
    break
  fi
  ((verify_attempt == 1)) && sleep 2
done
if ((verify_read == 0)); then
  verify_err_text="$(tr -d '\r' <"$verify_err" | tr '\n' ' ')"
  case "$verify_err_text" in
  *"HTTP 404"*)
    verify_verdict="comment $new_id is GONE — the write landed and the comment no longer exists (deleted, or the issue was); the next cycle will create a fresh one"
    ;;
  *) verify_verdict="$unconfirmed" ;;
  esac
  verify_fail "could not re-read comment $new_id after 2 attempts (gh api GET): $verify_err_text" "$verify_verdict"
fi

case "$verify_body" in
*"$SENTINEL"*) : ;;
*) verify_fail "comment $new_id does not carry the marker sentinel after the write" ;;
esac

# Everything below the sentinel is the caller's body — the sentinel is ours and
# would otherwise mask a leading `@` in the part that carries the data.
verify_rest="${verify_body#*"$SENTINEL"}"
verify_rest="${verify_rest#$'\n'}"

# The body that was sent cleared the same two assertions pre-write, so failing
# them now means the stored comment diverged from it afterwards. Naming that
# keeps an operator from hunting a caller-side `@path` bug the gate excluded.
[[ "$verify_rest" == @* ]] &&
  verify_fail "comment $new_id starts with a literal '@' below the sentinel, but the body sent did not — the stored comment diverged from what was written"

verify_bytes="$(printf '%s' "$verify_rest" | wc -c | tr -d ' ')"
((verify_bytes >= MIN_BODY_BYTES)) ||
  verify_fail "comment $new_id carries ${verify_bytes} bytes below the sentinel, under the ${MIN_BODY_BYTES}-byte floor — a comment that looks fresh but holds no telemetry"

printf 'telemetry-upsert: %sd comment %s (marker=%s) on %s#%s\n' \
  "$action" "$new_id" "$MARKER" "$REPO" "$ISSUE"
[[ -n "$html_url" ]] && printf '%s\n' "$html_url"
# Explicit: without it a response carrying no html_url leaves the `[[ ]] &&`
# above as the last command, and a verified upsert would exit 1.
exit 0
