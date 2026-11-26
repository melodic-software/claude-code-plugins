#!/usr/bin/env bash
set -uo pipefail # -e omitted: gh api failures explicitly guarded with || { exit N }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_NUMBER=""
CHECKOUT=""

usage() {
  cat <<'EOF'
fetch-all-pr-comments.sh: fetch a PR's general, review and inline comments as one JSON array.

Usage:
  fetch-all-pr-comments.sh <pr-number> [--dir <checkout>]

  --dir  any checkout of the PR's repository (default: the current directory)
  FETCH_COMMENTS_OWNER and FETCH_COMMENTS_REPO win over --dir and the default.

Exit codes:
  0  success (zero or more comments emitted)
  1  invalid argument, or --dir names no directory
  2  gh api call failed, or jq failed parsing a surface or merging
  5  prerequisite missing (gh, jq)
EOF
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
  --dir)
    if (($# < 2)) || [[ -z "$2" || -n "$CHECKOUT" ]]; then
      printf 'fetch-all-pr-comments: --dir needs one value and is given once\n' >&2
      exit 1
    fi
    CHECKOUT="$2"
    shift 2
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
if [[ -n "$CHECKOUT" && ! -d "$CHECKOUT" ]]; then
  printf 'fetch-all-pr-comments: --dir %q is not a directory\n' "$CHECKOUT" >&2
  exit 1
fi

have() { command -v "$1" >/dev/null 2>&1; }

have gh || {
  printf 'fetch-all-pr-comments: gh CLI required\n' >&2
  exit 5
}
have jq || {
  printf 'fetch-all-pr-comments: jq required\n' >&2
  exit 5
}

if [[ -n "$CHECKOUT" ]]; then
  OWNER_REPO=""
  [[ -n "${FETCH_COMMENTS_OWNER:-}" && -n "${FETCH_COMMENTS_REPO:-}" ]] ||
    OWNER_REPO=$(bash "$SCRIPT_DIR/../skills/pull-request/scripts/target-repo.sh" --dir "$CHECKOUT" | tr -d '\r\n')
  OWNER=${FETCH_COMMENTS_OWNER:-${OWNER_REPO%%/*}}
  REPO=${FETCH_COMMENTS_REPO:-${OWNER_REPO#*/}}
  if [[ -z "$OWNER" || -z "$REPO" ]]; then
    printf 'fetch-all-pr-comments: cannot resolve owner/repo for --dir %q (see target-repo above), or set FETCH_COMMENTS_OWNER + FETCH_COMMENTS_REPO.\n' "$CHECKOUT" >&2
    exit 2
  fi
else
  OWNER=${FETCH_COMMENTS_OWNER:-$(gh repo view --json owner -q .owner.login 2>/dev/null | tr -d '\r\n')}
  REPO=${FETCH_COMMENTS_REPO:-$(gh repo view --json name -q .name 2>/dev/null | tr -d '\r\n')}
fi

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  printf 'fetch-all-pr-comments: cannot resolve owner/repo - gh repo view found no repository for the current directory (%s). Run from a checkout of the target repo, or set FETCH_COMMENTS_OWNER + FETCH_COMMENTS_REPO.\n' "$PWD" >&2
  exit 2
fi

ALL_JSON=""
fetch_surface() {
  local endpoint="$1" projection="$2" raw json
  raw=$(gh api --paginate "repos/$OWNER/$REPO/$endpoint?per_page=100" 2>/dev/null) || {
    printf 'fetch-all-pr-comments: gh api %s failed\n' "$endpoint" >&2
    exit 2
  }
  json=$(printf '%s' "$raw" |
    jq -c 'if type == "array" then .[] else . end | '"$projection" 2>/dev/null) || {
    printf 'fetch-all-pr-comments: jq failed parsing %s response\n' "$endpoint" >&2
    exit 2
  }
  [[ -z "$json" ]] || ALL_JSON+="$json"$'\n'
}

fetch_surface "issues/$PR_NUMBER/comments" '
  {
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

fetch_surface "pulls/$PR_NUMBER/reviews" '
  select(.body != null and .body != "")
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

fetch_surface "pulls/$PR_NUMBER/comments" '
  {
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

printf '%s' "$ALL_JSON" | jq -s 'sort_by(.created_at)' || {
  printf 'fetch-all-pr-comments: jq merge failed\n' >&2
  exit 2
}
