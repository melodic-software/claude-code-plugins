#!/usr/bin/env bash
# fetch-all-pr-comments.sh — Fetch ALL PR comments across 3 GitHub API surfaces.
#
# Deterministic replacement for agent judgment in endpoint selection.
# Hits all three surfaces that can carry review feedback:
#   1. General PR comments (issue-level conversation tab)
#   2. Review-level comments (review summaries)
#   3. Inline review comments (line-anchored on the diff)
#
# Output: unified JSON array sorted by creation date. Each object:
#   {"id":N,"type":"general|review|inline","author":"login","body":"...","path":"...","line":N,"created_at":"ISO","in_reply_to_id":N|null}
#
# in_reply_to_id is populated ONLY for type "inline" (the only GitHub REST
# surface that threads via this field — general/review comments have no
# reply-parent concept and always carry null). GitHub sets it to the id of
# the THREAD-OPENING comment, not the immediately-preceding reply: every
# reply in a thread carries the same in_reply_to_id (empirically verified
# against live review-thread data — every referenced parent in that set was
# itself a root comment), so grouping by `in_reply_to_id // id` recovers
# thread membership directly. This does not change the documented REST
# cross-check in reference/review-discipline.md / skills/pull-request/SKILL.md
# — this script's schema was the only thing missing the field; the raw API
# was always correct.
#
# Usage:
#   fetch-all-pr-comments.sh <pr-number>
#
# Env overrides:
#   FETCH_COMMENTS_OWNER   default `gh repo view --json owner -q .owner.login`
#   FETCH_COMMENTS_REPO    default `gh repo view --json name -q .name`
#
# Windows Python consumers (#597):
#   Output commonly carries non-ASCII bytes (bot badge images, reaction
#   emoji) from bot review comments. A downstream Python consumer on Windows
#   that opens the JSON output, or reads this script's stdout, WITHOUT an
#   explicit UTF-8 encoding inherits the interpreter's default ANSI code page
#   (cp1252) and raises UnicodeDecodeError on those bytes. Either open with
#   `encoding="utf-8"` (or reconfigure the stream to UTF-8 at runtime), or run
#   the consumer with `PYTHONUTF8=1` (PEP 540) set in the environment.
#
# Exit codes:
#   0  success (zero or more comments emitted)
#   1  invalid argument
#   2  gh api call failed
#   5  prerequisite missing (gh, jq)

set -uo pipefail # -e omitted: gh api failures explicitly guarded with || { exit N }

# --- Argument parsing --------------------------------------------------------

PR_NUMBER=""

usage() {
  sed -n '2,39p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --)
    shift
    if [[ -z "$PR_NUMBER" && $# -gt 0 ]]; then
      PR_NUMBER="$1"
      shift
    fi
    if [[ $# -gt 0 ]]; then
      printf 'fetch-all-pr-comments: unexpected argument after --: %q\n' "$1" >&2
      exit 1
    fi
    break
    ;;
  -*)
    printf 'fetch-all-pr-comments: unknown flag %q (use --help)\n' "$1" >&2
    exit 1
    ;;
  *)
    if [[ -z "$PR_NUMBER" ]]; then
      PR_NUMBER="$1"
    else
      printf 'fetch-all-pr-comments: unexpected argument %q\n' "$1" >&2
      exit 1
    fi
    shift
    ;;
  esac
done

if [[ -z "$PR_NUMBER" ]]; then
  printf 'fetch-all-pr-comments: <pr-number> required\n' >&2
  exit 1
fi

# --- Prerequisites -----------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

have gh || {
  printf 'fetch-all-pr-comments: gh CLI required\n' >&2
  exit 5
}
have jq || {
  printf 'fetch-all-pr-comments: jq required\n' >&2
  exit 5
}

# --- Repo resolution ---------------------------------------------------------

if [[ -n "${FETCH_COMMENTS_OWNER:-}" ]]; then
  OWNER="$FETCH_COMMENTS_OWNER"
else
  OWNER=$(gh repo view --json owner -q .owner.login 2>/dev/null | tr -d '\r\n')
fi

if [[ -n "${FETCH_COMMENTS_REPO:-}" ]]; then
  REPO="$FETCH_COMMENTS_REPO"
else
  REPO=$(gh repo view --json name -q .name 2>/dev/null | tr -d '\r\n')
fi

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  printf 'fetch-all-pr-comments: cannot resolve owner/repo - gh repo view found no repository for the current directory (%s). Run from a checkout of the target repo, or set FETCH_COMMENTS_OWNER + FETCH_COMMENTS_REPO.\n' "$PWD" >&2
  exit 2
fi

# --- Surface fetch -----------------------------------------------------------

# fetch_surface <endpoint> <jq-projection> — page one API surface and project it
# into the shared schema, leaving the JSONL in SURFACE_JSON. Every surface has
# the same two failure modes (the fetch, then the parse) and the same fail-loud
# response to each, so they live here once rather than per surface.
#
# The result comes back through a GLOBAL rather than stdout: both guards must
# terminate the SCRIPT, and an `exit 2` inside a `$( )` capture kills only the
# subshell — the caller would sail on with an empty surface, which is exactly
# the shape of a PR with no comments there.
SURFACE_JSON=""
fetch_surface() {
  local endpoint="$1" projection="$2" raw
  SURFACE_JSON=""
  raw=$(gh api --paginate "repos/$OWNER/$REPO/$endpoint" 2>/dev/null) || {
    printf 'fetch-all-pr-comments: gh api %s failed\n' "$endpoint" >&2
    exit 2
  }
  SURFACE_JSON=$(printf '%s' "$raw" | jq -c "$projection" 2>/dev/null) || {
    printf 'fetch-all-pr-comments: jq failed parsing %s response\n' "$endpoint" >&2
    exit 2
  }
}

# --- Surface 1: General PR comments (issue-level) ----------------------------

fetch_surface "issues/$PR_NUMBER/comments" '
  if type == "array" then .[] else . end
  | {
      id: .id,
      type: "general",
      author: .user.login,
      body: .body,
      path: null,
      line: null,
      created_at: .created_at,
      in_reply_to_id: null
    }
'
GENERAL="$SURFACE_JSON"

# --- Surface 2: Review-level comments ----------------------------------------

fetch_surface "pulls/$PR_NUMBER/reviews" '
  if type == "array" then .[] else . end
  | select(.body != null and .body != "")
  | {
      id: .id,
      type: "review",
      author: .user.login,
      body: .body,
      path: null,
      line: null,
      created_at: (.submitted_at // .created_at),
      in_reply_to_id: null
    }
'
REVIEWS="$SURFACE_JSON"

# --- Surface 3: Inline review comments (line-anchored) -----------------------

fetch_surface "pulls/$PR_NUMBER/comments" '
  if type == "array" then .[] else . end
  | {
      id: .id,
      type: "inline",
      author: .user.login,
      body: .body,
      path: .path,
      line: (.line // .original_line),
      created_at: .created_at,
      in_reply_to_id: .in_reply_to_id
    }
'
INLINE="$SURFACE_JSON"

# --- Merge and sort by created_at --------------------------------------------

{
  [[ -n "$GENERAL" ]] && printf '%s\n' "$GENERAL"
  [[ -n "$REVIEWS" ]] && printf '%s\n' "$REVIEWS"
  [[ -n "$INLINE" ]] && printf '%s\n' "$INLINE"
} | jq -s 'sort_by(.created_at)'

exit 0
