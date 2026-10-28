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
# The branch it would push (named, current, or the --pr head) refuses when it is
# main, master, or the push remote's default branch as `git ls-remote --symref`
# reports it; a read that fails or names no default refuses too. A --pr head in
# a fork of the base repository is exempt: that push goes to the fork. `--check` runs only that check
# (create.md calls it before opening a PR) and pushes nothing.
#
# Inside a lane (the acting gh login is a GitHub App `[bot]` login) none of the
# above runs: the push goes to the plugin's scripts/lane-push.sh (see the lane
# block below), and --pr for a fork head needs --dir.
#
# sync-stale-base: on the operator path, just before the push, a branch behind
# its base on overlapping paths gets the base merged in, so a pre-push hook
# that refuses a stale base with overlapping paths does not bounce a push that
# waited in a rate gate while the base moved. The base is the PR's base branch
# (--pr's own read, else `gh pr view <branch>`), or the fetch remote's default
# branch when the branch has no PR yet. It is fetched from the remote whose URL
# is the PR's base repository on github.com (the fetch remote when there is no
# PR); with no such remote the step is skipped. Nothing the pushed head holds
# decides the step or runs in it: the overlap rule is the base ref's
# scripts/check-stale-base-overlap.sh (with the base's scripts/ beside it),
# run as --check <remote>/<base> (exit 1 merges, 0 does not, anything else
# skips), else paths changed on both sides since the merge-base.
# The merge is `git merge --no-edit`, never a rebase, signed when
# commit.gpgsign is true (git's own setting) or HEAD is signed (-S). It is
# skipped, with a note, when the base cannot be read or fetched, the branch is
# checked out in no worktree, tracked files have uncommitted edits, or a merge
# is in progress. A conflict aborts the merge and exits 4 without pushing.
# On: sync_stale_base: true in docs/conventions/source-control.yaml at the
# base repository's default branch, as this clone last fetched it (no network
# read; without --pr the base repository is asked of the forge only when some
# fetched remote turns the setting on), or --sync-stale-base;
# --no-sync-stale-base
# turns it off. Off by default. A lane (below) never syncs. --check never syncs.
#
# Exit: 0 pushed (or --check passed); 1 refused or the push failed; 4 the
# sync-stale-base merge conflicted and was aborted, nothing pushed.
#
# Usage: push-branch.sh [--check] [--dir <checkout>] [--sync-stale-base | --no-sync-stale-base]
#                       [branch-name | --pr <number>]
#   (options in any order; defaults to the current branch; any other argument
#   refuses)
set -uo pipefail

# portability-scope: --pr resolves the pull request's head branch and head repository through gh, and a lane its base repository and identity.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-remote.sh"
CONVENTION_KEY="${SCRIPT_DIR}/../../../lib/convention-key.sh"

DIR=""
BRANCH=""
PR=""
HAS_DIR=""
HAS_PR=""
CHECK=""
SYNC=""
while (($#)); do
  case "$1" in
    --check)
      CHECK=1
      shift
      ;;
    --sync-stale-base | --no-sync-stale-base)
      if [[ -n "$SYNC" ]]; then
        echo "push-branch.sh: --sync-stale-base and --no-sync-stale-base are given once, one of them; not pushing" >&2
        exit 1
      fi
      SYNC=true
      [[ "$1" == --sync-stale-base ]] || SYNC=false
      shift
      ;;
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
  # The PR's URL names its base repository.
  read -r BRANCH HEAD_REPO PR_BASE_REPO PR_BASE_REF < <(gh pr view "$PR" --json headRefName,headRepository,headRepositoryOwner,url,baseRefName \
    -q '.headRefName + " " + .headRepositoryOwner.login + "/" + .headRepository.name + " " + (.url | split("/")[3:5] | join("/")) + " " + .baseRefName' 2>/dev/null | tr -d '\r')
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

# remote_default <remote>: the remote's default branch as `ls-remote --symref`
# reports it, or nothing.
remote_default() {
  local out
  out=$(git ls-remote --symref "$1" HEAD 2>/dev/null) || return 0
  sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]HEAD$|\1|p' <<<"${out//$'\r'/}"
}

# github_repo_of <url>: the owner/repo a github.com URL (https, ssh:// or
# scp-style) names, or nothing.
github_repo_of() {
  local url="${1%/}"
  url="${url%.git}"
  case "${url,,}" in
    https://github.com/*) echo "${url:19}" ;;
    ssh://git@github.com/*) echo "${url:21}" ;;
    git@github.com:*) echo "${url:15}" ;;
    *) ;;
  esac
}

# remote_of_repo <owner/repo>: the first remote whose fetch URL is that
# github.com repository, or nothing.
remote_of_repo() {
  local r repo
  for r in $(git remote); do
    repo=$(github_repo_of "$(git remote get-url "$r" 2>/dev/null)")
    if [[ -n "$repo" && "${repo,,}" == "${1,,}" ]]; then
      echo "$r"
      return 0
    fi
  done
}

# worktree_of <branch>: the worktree that has <branch> checked out, or nothing.
worktree_of() {
  local line wt=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) wt="${line#worktree }" ;;
      "branch refs/heads/$1")
        echo "$wt"
        return 0
        ;;
      *) ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
}

# refuse_default <remote> <branch>: exit 1 when <branch> is main, master, or
# <remote>'s default branch. The default is read from the remote itself
# (`ls-remote --symref`), never the local <remote>/HEAD, which can be unset or
# stale. A failed read refuses, and so does a read that names no default (an
# empty remote, a server that does not advertise the symref, a detached HEAD).
refuse_default() {
  local default="" what="'$2'"
  # A fork head pushes to the contributor's fork, never the base repository, so
  # its default branch may be pushed (lane-push.sh's is_fork rule). An unread
  # base repository counts as no fork.
  if [[ -n "$PR" ]]; then
    if [[ -n "${PR_BASE_REPO:-}" && "${HEAD_REPO,,}" != "${PR_BASE_REPO,,}" ]]; then
      return 0
    fi
    what="PR '$PR' head '$2'"
  fi
  default=$(remote_default "$1")
  if [[ -z "$default" ]]; then
    echo "push-branch.sh: the default branch of $1 could not be read (git ls-remote failed or named no HEAD branch); not pushing" >&2
    exit 1
  fi
  if [[ "$2" == "$default" ]]; then
    echo "push-branch.sh: $what is the default branch of $1; not pushing" >&2
    exit 1
  fi
  if [[ "$2" == main || "$2" == master ]]; then
    echo "push-branch.sh: $what is refused (main and master are always refused); not pushing" >&2
    exit 1
  fi
}

if [[ -n "$CHECK" ]]; then
  if [[ -z "$BRANCH" ]]; then
    echo "push-branch.sh: no branch to check (detached HEAD?); not pushing" >&2
    exit 1
  fi
  CHECK_REMOTE=$(bash "$RESOLVER" --push "$BRANCH") || exit 1
  refuse_default "$CHECK_REMOTE" "$BRANCH"
  exit 0
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
  if [[ -n "$DIR" ]]; then
    SRC_DIR=$(pwd -P)
  else
    SRC_DIR=$(worktree_of "$BRANCH")
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
# Never push main, master or the push remote's default branch (a cwd that reset
# to the main checkout would otherwise push main).
[[ -z "$BRANCH" ]] || refuse_default "$PUSH_REMOTE" "$BRANCH"
# A same-named local branch is not the PR's head unless every URL the push
# writes to is the PR's head repository on github.com (a fork PR's head lives
# on the fork). The URLs are read after insteadOf rewriting, as git pushes them.
if [[ -n "${HEAD_REPO:-}" ]]; then
  URLS=$(git remote get-url --push --all "$PUSH_REMOTE" 2>/dev/null)
  while IFS= read -r URL; do
    URL_REPO=$(github_repo_of "$URL")
    if [[ -z "$URL_REPO" || "${URL_REPO,,}" != "${HEAD_REPO,,}" ]]; then
      echo "push-branch.sh: '$BRANCH' pushes to '$PUSH_REMOTE' ($URL), not PR '$PR' head repository '$HEAD_REPO' on github.com (https://github.com/, ssh://git@github.com/ or git@github.com:); not pushing" >&2
      exit 1
    fi
  done <<<"$URLS"
fi

FETCH_REMOTE=$(bash "$RESOLVER" "$BRANCH" 2>/dev/null)

sync_skip() { echo "push-branch.sh: sync-stale-base skipped: $1; pushing as is" >&2; }

# local_default <remote>: <remote>'s default branch as this clone last fetched
# it (the refs/remotes/<remote>/HEAD symref, else the first of main, master or
# trunk it holds), or nothing. No network call.
local_default() {
  local d b
  d=$(git symbolic-ref --short "refs/remotes/$1/HEAD" 2>/dev/null) && {
    echo "${d#"$1"/}"
    return 0
  }
  for b in main master trunk; do
    git rev-parse -q --verify "refs/remotes/$1/$b" >/dev/null && {
      echo "$b"
      return 0
    }
  done
}

# setting_at <remote>: sync_stale_base in docs/conventions/source-control.yaml
# on <remote>'s default branch as this clone last fetched it, or nothing.
setting_at() {
  local d out tmp on=""
  d=$(local_default "$1")
  [[ -n "$d" ]] || return 0
  out=$(git show "refs/remotes/$1/$d:docs/conventions/source-control.yaml" 2>/dev/null) || return 0
  tmp=$(mktemp -d) || return 0
  mkdir -p "$tmp/docs/conventions" && printf '%s\n' "$out" >"$tmp/docs/conventions/source-control.yaml"
  on=$(bash "$CONVENTION_KEY" value "$tmp" sync_stale_base) ||
    echo "push-branch.sh: $1/$d:docs/conventions/source-control.yaml does not parse; sync_stale_base read as false" >&2
  rm -rf "$tmp"
  echo "$on"
}

# sync_stale_base <checkout>: the sync-stale-base step of the header. Returns
# 0 to push; exits 4 on a conflict. Nothing the pushed head holds decides
# whether it runs or is run by it: the setting is read from the base
# repository's default branch and the overlap script from the base ref. With
# the setting unset everywhere this clone has fetched, it makes no network call.
sync_stale_base() {
  local wd="$1" on="$SYNC" base="${PR_BASE_REF:-}" base_repo="${PR_BASE_REPO:-}" remote="$FETCH_REMOTE"
  local tmp out ref rc mb tip paths_base paths_head overlap r sign=()
  [[ "$on" != false ]] || return 0
  [[ -z "$base_repo" ]] || remote=$(cd "${wd:-.}" && remote_of_repo "$base_repo")
  if [[ -z "$on" && -z "$PR" ]]; then
    # The base repository is not known yet: it takes a forge read, made only
    # when some remote's fetched default branch turns the setting on.
    for r in $(cd "${wd:-.}" && git remote); do
      [[ "$(cd "${wd:-.}" && setting_at "$r")" != true ]] || on=pending
    done
    [[ -n "$on" ]] || return 0
  elif [[ -z "$on" ]]; then
    [[ -n "$remote" && "$(cd "${wd:-.}" && setting_at "$remote")" == true ]] || return 0
    on=true
  fi
  [[ -n "$wd" ]] || {
    sync_skip "'$BRANCH' is checked out in no worktree"
    return 0
  }
  if [[ -z "$PR" ]]; then
    if out=$(gh pr view "$BRANCH" --json baseRefName,url -q '.baseRefName + " " + (.url | split("/")[3:5] | join("/"))' 2>&1); then
      read -r base base_repo <<<"${out//$'\r'/}"
      remote=$(cd "$wd" && remote_of_repo "$base_repo")
    elif [[ "$out" == *"no pull requests found"* ]]; then
      base=$(cd "$wd" && local_default "$FETCH_REMOTE")
      [[ -n "$base" ]] || base=$(cd "$wd" && remote_default "$FETCH_REMOTE")
    fi
    # With no remote for the base repository, the skip below says so.
    if [[ "$on" == pending && -n "$remote" ]]; then
      [[ "$(cd "$wd" && setting_at "$remote")" == true ]] || return 0
    fi
  fi
  [[ -n "$remote" ]] || {
    sync_skip "no remote fetches the base repository ${base_repo:-of $BRANCH}"
    return 0
  }
  [[ -n "$base" ]] || {
    sync_skip "the base branch of '$BRANCH' could not be read"
    return 0
  }
  ref="$remote/$base"
  git -C "$wd" fetch --quiet "$remote" "+refs/heads/$base:refs/remotes/$ref" || {
    sync_skip "git fetch of $ref failed"
    return 0
  }
  git -C "$wd" diff --quiet HEAD -- || {
    sync_skip "tracked files in $wd have uncommitted edits"
    return 0
  }
  ! git -C "$wd" rev-parse -q --verify MERGE_HEAD >/dev/null || {
    sync_skip "a merge is in progress in $wd"
    return 0
  }
  if git -C "$wd" cat-file -e "$ref:scripts/check-stale-base-overlap.sh" 2>/dev/null; then
    # The base's copy of the repository's rule (and the libraries beside it),
    # never the pushed head's.
    tmp=$(mktemp -d) || return 0
    git -C "$wd" archive "$ref" -- scripts | tar -x -C "$tmp"
    (cd "$wd" && bash "$tmp/scripts/check-stale-base-overlap.sh" --check "$ref") >&2
    rc=$?
    rm -rf "$tmp"
    ((rc != 0)) || return 0
    ((rc == 1)) || {
      sync_skip "the base's scripts/check-stale-base-overlap.sh exited $rc"
      return 0
    }
  else
    if ! mb=$(git -C "$wd" merge-base HEAD "$ref") || ! tip=$(git -C "$wd" rev-parse "$ref^{commit}") ||
      ! paths_base=$(git -C "$wd" diff --name-only --no-renames "$mb" "$tip") ||
      ! paths_head=$(git -C "$wd" diff --name-only --no-renames "$mb" HEAD); then
      sync_skip "the paths changed since the merge-base of HEAD and $ref could not be read"
      return 0
    fi
    [[ "$mb" != "$tip" ]] || return 0
    overlap=$(LC_ALL=C comm -12 <(LC_ALL=C sort -u <<<"$paths_base") <(LC_ALL=C sort -u <<<"$paths_head"))
    [[ -n "${overlap//$'\n'/}" ]] || return 0
  fi
  out=$(git -C "$wd" cat-file commit HEAD)
  if [[ "$(git -C "$wd" config --bool commit.gpgsign)" != true && "$out" =~ (^|$'\n')gpgsig(-sha256)?\  ]]; then
    sign=(-S)
  fi
  if git -C "$wd" merge --no-edit ${sign[@]+"${sign[@]}"} "$ref" >&2; then
    echo "push-branch.sh: merged $ref into '$BRANCH' (stale base with overlapping paths); HEAD is now $(git -C "$wd" rev-parse HEAD)" >&2
    return 0
  fi
  out=$(git -C "$wd" diff --name-only --diff-filter=U)
  git -C "$wd" merge --abort 2>/dev/null
  if [[ -n "$out" ]]; then
    echo "push-branch.sh: merging $ref into '$BRANCH' conflicted; merge aborted; not pushing. Merge it by hand (/source-control:resolve-conflicts), then push again" >&2
    exit 4
  fi
  echo "push-branch.sh: merging $ref into '$BRANCH' failed; not pushing" >&2
  exit 1
}

if [[ -n "$DIR" ]]; then
  sync_stale_base "$(pwd -P)"
  exec git push "$PUSH_REMOTE" "HEAD:refs/heads/$BRANCH"
fi
[[ -z "$BRANCH" ]] || sync_stale_base "$(worktree_of "$BRANCH")"
EXISTING_REMOTE=$(git config "branch.${BRANCH}.remote" 2>/dev/null)
EXISTING_MERGE=$(git config "branch.${BRANCH}.merge" 2>/dev/null)

if [[ -z "$EXISTING_REMOTE" && -z "$EXISTING_MERGE" && "$FETCH_REMOTE" == "$PUSH_REMOTE" ]]; then
  git push -u "$PUSH_REMOTE" "$BRANCH"
else
  git push "$PUSH_REMOTE" "$BRANCH"
fi
