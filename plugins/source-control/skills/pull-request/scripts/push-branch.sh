#!/usr/bin/env bash
# Push the current (or named) branch to its resolved push remote, setting
# upstream tracking (`-u`) ONLY for a branch that has no existing upstream and
# whose fetch and push remotes resolve to the same name.
#
# Push destination and fetch/rebase remote are resolved independently by the
# sibling resolve-remote.sh (Git lets them differ in a triangular fork flow):
#   PUSH_REMOTE  = resolve-remote.sh --push   (pushRemote -> pushDefault -> fetch order)
#   FETCH_REMOTE = resolve-remote.sh          (branch.<name>.remote -> origin -> sole other)
#
# `-u` is CONDITIONAL because `git push -u` rewrites the branch's ENTIRE upstream
# — both branch.<name>.remote AND branch.<name>.merge (to refs/heads/<name>). Two
# distinct ways that silently corrupts where the branch fetches/rebases from:
#
#   1. Retarget the remote. On a triangular fork (push to a fork via
#      pushRemote/pushDefault, fetch from origin/upstream) `-u` would repoint
#      branch.<name>.remote to the fork, so the next rebase targets the wrong
#      base. The trap is the shape where the fetch remote is NOT literally
#      configured but resolves via fallback: remote.pushDefault=fork with
#      branch.<name>.remote unset fetches from `origin` (fallback) yet pushes to
#      the fork.
#   2. Overwrite an existing upstream. The upstream is TWO keys —
#      branch.<name>.remote AND branch.<name>.merge — and `-u` rewrites both.
#      Any of these partial or full configs is an upstream the user chose that a
#      bootstrap must not clobber:
#        - both set to a real remote/ref (an ordinary tracked branch);
#        - branch.<name>.remote="." (a deliberate local-only upstream, e.g.
#          `git branch --track . <ref>`), merge naming the tracked local ref;
#        - branch.<name>.merge set with branch.<name>.remote UNSET — valid: Git
#          defaults the missing remote to `origin`, so the branch tracks
#          `origin/<merge-ref>`. `-u` here replaces the chosen merge ref with
#          refs/heads/<name>, the same clobber family as (1).
#
# The gate therefore fires `-u` only when BOTH hold:
#   * the branch has NO existing upstream — branch.<name>.remote AND
#     branch.<name>.merge are BOTH literally unset (a genuinely fresh feature
#     branch, nothing to preserve), AND
#   * FETCH_REMOTE == PUSH_REMOTE (bootstrapping tracking cannot misdirect the
#     fetch remote, because it can only be set to what fetch already resolves to).
# Any existing upstream — full, ".", or merge-only — is preserved by a plain
# push, which never writes branch config. An ambiguous fetch (FETCH_REMOTE empty:
# 2+ non-origin remotes, no origin) is unequal to any push remote -> plain push
# -> no write.
#
# The upstream-absent check reads both keys raw (no "." or CRLF normalization):
# any non-empty value -> "has an upstream" -> plain push preserves it; only the
# truly-unset (empty) keys are a bootstrap candidate. That normalized "."
# handling lives once, in resolve-remote.sh, and is not duplicated here.
#
# Push resolution must be determinate (it names the destination), so a failed
# --push resolution aborts; a failed fetch resolution does not.
#
# `--pr <number>` pushes that pull request's head branch, read from
# `gh pr view`, whatever worktree the caller runs in. Branch refs are shared
# across worktrees, so the push carries the commits made in the PR's worktree.
# A head branch with no local ref, a name starting with '-', or a push remote
# that is not the PR's head repository exits non-zero rather than pushing.
#
# Inside a lane (the acting gh login is a GitHub App `[bot]` login) none of the
# above runs: the push goes to the plugin's scripts/lane-push.sh (see the lane
# block below).
#
# Usage: push-branch.sh [branch-name | --pr <number>]   (defaults to the current branch)
set -uo pipefail

# portability-scope: --pr resolves the pull request's head branch and head repository through gh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-remote.sh"

BRANCH="${1:-}"
if [[ "$BRANCH" == "--pr" ]]; then
  PR="${2:-}"
  if [[ ! "$PR" =~ ^[0-9]+$ ]]; then
    echo "push-branch.sh: --pr needs a pull request number, got '$PR'; not pushing" >&2
    exit 1
  fi
  read -r BRANCH HEAD_REPO < <(gh pr view "$PR" --json headRefName,headRepository,headRepositoryOwner \
    -q '.headRefName + " " + .headRepositoryOwner.login + "/" + .headRepository.name' 2>/dev/null | tr -d '\r')
  if [[ "${BRANCH:-}" == -* ]]; then
    echo "push-branch.sh: PR '$PR' head branch '$BRANCH' starts with '-'; not pushing" >&2
    exit 1
  fi
  if [[ -z "${BRANCH:-}" ]] || ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "push-branch.sh: no local branch for the head of PR '$PR' ('${BRANCH:-}'); not pushing" >&2
    exit 1
  fi
elif [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null | tr -d '\r')"
fi

PUSH_REMOTE=$(bash "$RESOLVER" --push "$BRANCH") || exit 1
# A same-named local branch is not the PR's head unless its push remote is
# the PR's head repository (a fork PR's head lives on the fork).
if [[ -n "${HEAD_REPO:-}" ]]; then
  URL=$(git remote get-url "$PUSH_REMOTE" 2>/dev/null)
  URL="${URL%/}"
  URL="${URL%.git}"
  if [[ "${URL,,}" != *[:/]"${HEAD_REPO,,}" ]]; then
    echo "push-branch.sh: '$BRANCH' pushes to '$PUSH_REMOTE' ($URL), not PR '$PR' head repository '$HEAD_REPO'; not pushing" >&2
    exit 1
  fi
fi
# Inside a lane, hand the push to lane-push.sh (loop-lane convention, "Lane
# write identity"). A lane is a session whose acting gh login is a GitHub App
# login (`<slug>[bot]`): the identity contract requires one, and an operator
# never acts as one. lane-push.sh pushes HEAD of the worktree holding the
# branch to the https URL of the repository the push remote names, as that
# login. This check is advisory: a lane that skips this script is held only by
# the credentials its host gives it. A failed login read keeps the operator path.
ACTING=$(gh api --hostname github.com graphql -f 'query=query{viewer{login}}' \
  --jq .data.viewer.login 2>/dev/null | tr -d '\r')
if [[ "$ACTING" == *"[bot]" ]]; then
  URL=$(git remote get-url --push "$PUSH_REMOTE" 2>/dev/null)
  URL="${URL%/}"
  URL="${URL%.git}"
  case "$URL" in
    https://github.com/* | ssh://git@github.com/* | git@github.com:*) DEST_REPO="${URL#*github.com[:/]}" ;;
    *) DEST_REPO="" ;;
  esac
  if [[ ! "$DEST_REPO" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]]; then
    echo "push-branch.sh: lane push remote '$PUSH_REMOTE' ($URL) is not a github.com repository; not pushing" >&2
    exit 1
  fi
  SRC_DIR="" WT=""
  while IFS= read -r LINE; do
    case "$LINE" in
      "worktree "*) WT="${LINE#worktree }" ;;
      "branch refs/heads/$BRANCH")
        SRC_DIR="$WT"
        break
        ;;
      *) ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
  if [[ -z "$SRC_DIR" ]]; then
    echo "push-branch.sh: '$BRANCH' is checked out in no worktree, so lane-push.sh has no HEAD to push; not pushing" >&2
    exit 1
  fi
  exec bash "${SCRIPT_DIR}/../../../scripts/lane-push.sh" --dir "$SRC_DIR" --login "$ACTING" \
    --repo "$DEST_REPO" --branch "$BRANCH"
fi

FETCH_REMOTE=$(bash "$RESOLVER" "$BRANCH" 2>/dev/null)
EXISTING_REMOTE=$(git config "branch.${BRANCH}.remote" 2>/dev/null)
EXISTING_MERGE=$(git config "branch.${BRANCH}.merge" 2>/dev/null)

if [[ -z "$EXISTING_REMOTE" && -z "$EXISTING_MERGE" && "$FETCH_REMOTE" == "$PUSH_REMOTE" ]]; then
  git push -u "$PUSH_REMOTE" "$BRANCH"
else
  git push "$PUSH_REMOTE" "$BRANCH"
fi
