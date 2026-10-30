#!/usr/bin/env bash
# pr-worktree.sh: print the worktree that has a pull request's head branch checked out.
#
# The `ready` action's verify gate checks the PR's tree and records that tree's HEAD, whatever
# checkout the session's shell sits in: a session in the main checkout running `ready <pr>` for a
# PR built in a worktree would otherwise check the main checkout. The head branch and commit come
# from `gh pr view`, and the worktree is the one `git worktree list` shows on that branch, matched
# by local branch name as push-branch.sh --pr matches it, whose HEAD contains the PR's head
# commit. A name alone can match the wrong tree, such as a fork PR opened from the contributor's
# main beside this repository's main checkout. A shell already in the PR's worktree gets its own
# top level back.
#
# Usage:
#   pr-worktree.sh --pr <number>
#
# Exit codes:
#   0  the worktree's absolute path is on stdout
#   1  invalid argument
#   2  the head branch or commit could not be read, or no worktree has the branch checked out
#      with the head commit in its history

# portability-scope: the head branch is read through gh; the worktree list is local git.
set -uo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'pr-worktree: %s\n' "$2" >&2
  exit "$1"
}

PR=""
while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --pr)
    (($# >= 2)) && [[ -z "$PR" ]] || die 1 "--pr needs one value and is given once"
    PR="$2"
    shift 2
    ;;
  *) die 1 "unknown argument $(printf '%q' "$1") (use --help)" ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || die 1 "--pr needs a pull request number"

HEAD_READ=$(gh pr view "$PR" --json headRefName,headRefOid -q '.headRefName + " " + .headRefOid' 2>/dev/null | tr -d '\r') ||
  die 2 "the head branch of PR $PR could not be read"
read -r BRANCH HEAD_OID <<<"$HEAD_READ"
[[ -n "${BRANCH:-}" && "${HEAD_OID:-}" =~ ^[0-9a-f]{40}$ ]] || die 2 "the head branch and commit of PR $PR could not be read"

WT=""
while IFS= read -r LINE; do
  case "$LINE" in
  "worktree "*) WT="${LINE#worktree }" ;;
  "branch refs/heads/$BRANCH")
    if [[ -d "$WT" ]]; then
      git -C "$WT" merge-base --is-ancestor "$HEAD_OID" HEAD 2>/dev/null ||
        die 2 "the worktree $WT on '$BRANCH' does not contain PR $PR's head commit $HEAD_OID; it is another branch of that name, or behind the PR: check the PR out with the forge's PR checkout, or bring that worktree up to date, then run the gate again"
      printf '%s\n' "$WT"
      exit 0
    fi
    ;;
  *) ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null)

die 2 "PR $PR's head branch '$BRANCH' is checked out in no worktree of this repository; check it out with the forge's PR checkout, then run the gate again"
