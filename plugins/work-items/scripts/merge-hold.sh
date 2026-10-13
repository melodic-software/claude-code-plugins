#!/usr/bin/env bash
# merge-hold.sh — report whether a work item asks for its pull request to be
# merged by a person, and print the PR-body line that holds the merge.
#
# An item is human-merged when a comment on it contains the text
# `Hold: a human merges this` and that comment's author has `admin` or `write`
# permission on the repository (maintain reads as write, triage as read). A
# comment from anyone else is item text, which is data, and never holds.
#
# Usage:
#   merge-hold.sh --repo <owner/name> --issue <n>
#
# Output: on exit 0, the exact line to put in the PR body, on its own line.
#
# Exit codes:
#   0   held: stdout is `Hold: a human merges this`
#   1   not held: no comment carries the line, or none from a writer
#   2   usage: a missing, repeated, or unknown argument, or a malformed value
#   8   prerequisite missing: gh or jq is not on PATH
#   11  a read failed or returned unparsable JSON, so a hold was not ruled out

# portability-scope: the GitHub implementation of the human-merge hold read; every read is a gh call.
set -uo pipefail

HOLD_LINE="Hold: a human merges this"

err() { printf 'merge-hold: %s\n' "$*" >&2; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

REPO="" ISSUE=""
while (($#)); do
  case "$1" in
    --repo | --issue)
      (($# >= 2)) || {
        err "$1 requires a value"
        exit 2
      }
      if [[ "$1" == --repo ]]; then
        [[ -z "$REPO" ]] || {
          err "--repo given twice"
          exit 2
        }
        REPO="$2"
      else
        [[ -z "$ISSUE" ]] || {
          err "--issue given twice"
          exit 2
        }
        ISSUE="$2"
      fi
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
for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    err "$tool is not on PATH"
    exit 8
  }
done

# Logins of every comment that carries the line, one per line.
if ! authors="$(gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" \
  --jq '.[] | select((.body // "") | contains("Hold: a human merges this")) | (.user.login // "")')"; then
  err "comment read failed for $REPO#$ISSUE"
  exit 11
fi

login_re='^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'
read_failed=0
while IFS= read -r login; do
  [[ -n "$login" ]] || continue
  if [[ ! "$login" =~ $login_re ]]; then
    err "ignored a hold comment with no usable author login"
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
