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
# any of whose push URLs is not the PR's head repository on github.com (https,
# ssh:// or scp-style) exits non-zero rather than pushing.
#
# `--dir <checkout>` runs from that checkout and pushes its HEAD, detached
# included, to the branch by refspec, never with `-u`; with `--pr` the head
# branch needs no local ref. A babysit worker's worktree pushes this way.
#
# Inside a lane (the acting gh login is a GitHub App `[bot]` login) none of the
# above runs: the push goes to the plugin's scripts/lane-push.sh (see the lane
# block below), and --pr for a fork head needs --dir.
#
# Usage: push-branch.sh [--dir <checkout>] [branch-name | --pr <number>]
#   (options in any order; defaults to the current branch; any other argument
#   refuses)
set -uo pipefail

# portability-scope: --pr resolves the pull request's head branch and head repository through gh, and a lane its base repository and identity.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-remote.sh"

DIR=""
BRANCH=""
PR=""
HAS_DIR=""
HAS_PR=""
while (($#)); do
  case "$1" in
    --dir | --pr)
      if [[ $# -lt 2 || ("$1" == --dir && -n "$HAS_DIR") || ("$1" == --pr && -n "$HAS_PR") ]]; then
        echo "push-branch.sh: $1 needs one value and is given once; not pushing" >&2
        exit 1
      fi
      if [[ "$1" == --dir ]]; then
        HAS_DIR=1 DIR="$2"
      else
        HAS_PR=1 PR="$2"
      fi
      shift 2
      ;;
    -*)
      echo "push-branch.sh: unexpected argument '$1'; not pushing" >&2
      exit 1
      ;;
    *)
      if [[ -n "$BRANCH" ]]; then
        echo "push-branch.sh: unexpected argument '$1'; not pushing" >&2
        exit 1
      fi
      BRANCH="$1"
      shift
      ;;
  esac
done
if [[ -n "$HAS_PR" && -n "$BRANCH" ]]; then
  echo "push-branch.sh: unexpected argument '$BRANCH' beside --pr; not pushing" >&2
  exit 1
fi

if [[ -n "$HAS_DIR" ]] && { [[ -z "$DIR" ]] || ! cd -- "$DIR" 2>/dev/null; }; then
  echo "push-branch.sh: --dir needs a checkout directory, got '$DIR'; not pushing" >&2
  exit 1
fi

if [[ -n "$HAS_PR" ]]; then
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
  if [[ -z "${BRANCH:-}" ]] || { [[ -z "$DIR" ]] && ! git show-ref --verify --quiet "refs/heads/$BRANCH"; }; then
    echo "push-branch.sh: no local branch for the head of PR '$PR' ('${BRANCH:-}'); not pushing" >&2
    exit 1
  fi
elif [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null | tr -d '\r')"
fi

# Inside a lane, hand the push to lane-push.sh (loop-lane convention, "Lane
# write identity"). A lane is a session whose acting gh login is a GitHub App
# login (`<slug>[bot]`): the identity contract requires one, and an operator
# never acts as one. The push goes to the lane's base repository as the
# merge.agent-identity that repository's pr-pipeline.yaml names on its default
# branch: babysit-prs' identity preflight reads it and refuses unless the
# session acts as it and holds no other account, and lane-push.sh, given it as
# --login, refuses unless the token still acts as it at push time. With --pr,
# lane-push.sh reads the PR's head repository and branch itself; no remote or
# URL of this checkout is read. lane-push.sh pushes HEAD of --dir, else of the
# worktree holding the branch. This check is advisory: a lane that skips this
# script is held only by the credentials its host gives it. A failed login read
# keeps the operator path (residual R4).
ACTING=$(gh api --hostname github.com graphql -f 'query=query{viewer{login}}' \
  --jq .data.viewer.login 2>/dev/null | tr -d '\r')
if [[ "$ACTING" == *"[bot]" ]]; then
  BASE_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null | tr -d '\r')
  if [[ -z "$BASE_REPO" ]]; then
    echo "push-branch.sh: the lane's base repository could not be read; not pushing" >&2
    exit 1
  fi
  PREFLIGHT=$(bash "${SCRIPT_DIR}/../../babysit-prs/scripts/babysit-postmerge.sh" \
    --repo "$BASE_REPO" --preflight)
  PREFLIGHT_RC=$?
  IDENTITY=$(sed -n 's/^[[:space:]]*"identity":[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$PREFLIGHT")
  if [[ $PREFLIGHT_RC -ne 0 || -z "$IDENTITY" ]]; then
    echo "push-branch.sh: the lane identity preflight for $BASE_REPO refused; not pushing" >&2
    echo "$PREFLIGHT" >&2
    exit 1
  fi
  # A fork head's name can match a local branch of the base repository, which
  # is not the PR's head: a fork PR pushes only the checkout --dir names.
  if [[ -n "$PR" && -z "$DIR" && "${HEAD_REPO,,}" != "${BASE_REPO,,}" ]]; then
    echo "push-branch.sh: PR '$PR' head repository '$HEAD_REPO' is not '$BASE_REPO'; a lane pushes a fork head only with --dir; not pushing" >&2
    exit 1
  fi
  SRC_DIR=""
  if [[ -n "$DIR" ]]; then
    SRC_DIR=$(pwd -P)
  else
    WT=""
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
  fi
  if [[ -z "$SRC_DIR" ]]; then
    echo "push-branch.sh: '$BRANCH' is checked out in no worktree, so lane-push.sh has no HEAD to push; not pushing" >&2
    exit 1
  fi
  LANE_PUSH="${SCRIPT_DIR}/../../../scripts/lane-push.sh"
  if [[ -n "$PR" ]]; then
    exec bash "$LANE_PUSH" --dir "$SRC_DIR" --login "$IDENTITY" --repo "$BASE_REPO" --pr "$PR"
  fi
  exec bash "$LANE_PUSH" --dir "$SRC_DIR" --login "$IDENTITY" --repo "$BASE_REPO" --branch "$BRANCH"
fi

PUSH_REMOTE=$(bash "$RESOLVER" --push "$BRANCH") || exit 1
# A same-named local branch is not the PR's head unless every URL the push
# writes to is the PR's head repository on github.com (a fork PR's head lives
# on the fork). The URLs are read after insteadOf rewriting, as git pushes them.
if [[ -n "${HEAD_REPO:-}" ]]; then
  URLS=$(git remote get-url --push --all "$PUSH_REMOTE" 2>/dev/null)
  while IFS= read -r URL; do
    URL="${URL%/}"
    URL="${URL%.git}"
    URL_REPO=""
    case "${URL,,}" in
      https://github.com/*) URL_REPO="${URL:19}" ;;
      ssh://git@github.com/*) URL_REPO="${URL:21}" ;;
      git@github.com:*) URL_REPO="${URL:15}" ;;
      *) ;;
    esac
    if [[ -z "$URL_REPO" || "${URL_REPO,,}" != "${HEAD_REPO,,}" ]]; then
      echo "push-branch.sh: '$BRANCH' pushes to '$PUSH_REMOTE' ($URL), not PR '$PR' head repository '$HEAD_REPO' on github.com (https://github.com/, ssh://git@github.com/ or git@github.com:); not pushing" >&2
      exit 1
    fi
  done <<<"$URLS"
fi

if [[ -n "$DIR" ]]; then
  exec git push "$PUSH_REMOTE" "HEAD:refs/heads/$BRANCH"
fi

FETCH_REMOTE=$(bash "$RESOLVER" "$BRANCH" 2>/dev/null)
EXISTING_REMOTE=$(git config "branch.${BRANCH}.remote" 2>/dev/null)
EXISTING_MERGE=$(git config "branch.${BRANCH}.merge" 2>/dev/null)

if [[ -z "$EXISTING_REMOTE" && -z "$EXISTING_MERGE" && "$FETCH_REMOTE" == "$PUSH_REMOTE" ]]; then
  git push -u "$PUSH_REMOTE" "$BRANCH"
else
  git push "$PUSH_REMOTE" "$BRANCH"
fi
