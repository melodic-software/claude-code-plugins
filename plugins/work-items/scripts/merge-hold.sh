#!/usr/bin/env bash
# Exit codes:
#   0   held: stdout is `Hold: a human merges this`
#   1   not held: no comment carries the line, or none from a writer
#   2   usage: a missing, repeated, or unknown argument, or a malformed value
#   8   prerequisite missing: gh is not on PATH
#   11  a read failed or returned unparsable JSON, so a hold was not ruled out

# portability-scope: the GitHub implementation of the human-merge hold read; every read is a gh call.
set -uo pipefail

HOLD_LINE="Hold: a human merges this"

err() { printf 'merge-hold: %s\n' "$*" >&2; }
usage() {
  cat <<'TXT'
Report whether a work item holds its pull request for a human merge, and print the PR-body hold line.

Usage: merge-hold.sh --repo <owner/name> --issue <n>
  --repo   the repository, owner/name
  --issue  the work item's issue number

Exit 0 held (stdout is the hold line); 1 not held; 2 usage; 8 gh not on PATH; 11 a read failed, so a hold was not ruled out.
TXT
}

REPO="" ISSUE=""
while (($#)); do
  case "$1" in
    --repo | --issue)
      (($# >= 2)) || {
        err "$1 requires a value"
        exit 2
      }
      var=REPO
      [[ "$1" == --repo ]] || var=ISSUE
      [[ -z "${!var}" ]] || {
        err "$1 given twice"
        exit 2
      }
      printf -v "$var" '%s' "$2"
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
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  err "--repo must be owner/name"
  exit 2
}
[[ "$ISSUE" =~ ^[1-9][0-9]*$ ]] || {
  err "--issue must be a positive integer"
  exit 2
}
command -v gh >/dev/null 2>&1 || {
  err "gh is not on PATH"
  exit 8
}

if ! authors="$(gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" \
  --jq ".[] | select((.body // \"\") | contains(\"$HOLD_LINE\")) | (.user.login // \"\")")"; then
  err "comment read failed for $REPO#$ISSUE"
  exit 11
fi

login_re='^[A-Za-z0-9][A-Za-z0-9_-]*(\[bot\])?$'
read_failed=0
while IFS= read -r login; do
  [[ -n "$login" ]] || continue
  if [[ ! "$login" =~ $login_re ]]; then
    err "hold comment author login is not a usable path segment"
    read_failed=1
    continue
  fi
  if ! perm="$(gh api "repos/$REPO/collaborators/$login/permission" --jq '.permission // ""' 2>/dev/null)"; then
    err "permission read failed for $login"
    read_failed=1
    continue
  fi
  case "$perm" in
    admin | write)
      printf '%s\n' "$HOLD_LINE"
      exit 0
      ;;
    *) err "ignored a hold comment by $login (permission ${perm:-none})" ;;
  esac
done < <(sort -u <<<"$authors")

((read_failed)) && exit 11
exit 1
