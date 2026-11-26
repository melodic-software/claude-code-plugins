#!/usr/bin/env bash
set -uo pipefail

# portability-scope: --pr resolves the pull request's head branch and head repository through gh, and a lane its base repository and identity.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-remote.sh"
CONVENTION_KEY="${SCRIPT_DIR}/../../../lib/convention-key.sh"
# shellcheck source=../../../lib/github-remote.sh
source "${SCRIPT_DIR}/../../../lib/github-remote.sh"

DIR=""
BRANCH=""
PR=""
HAS_DIR=""
HAS_PR=""
CHECK=""
PRE_PUSH=""
SYNC=""
while (($#)); do
  case "$1" in
    --check)
      CHECK=1
      shift
      ;;
    --preflight)
      PRE_PUSH=1
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
if [[ -n "$CHECK" && -n "$PRE_PUSH" ]]; then
  echo "push-branch.sh: --check and --preflight are given one at a time; not pushing" >&2
  exit 1
fi
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

remote_default() {
  local out
  out=$(git ls-remote --symref "$1" HEAD 2>/dev/null) || return 0
  sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]HEAD$|\1|p' <<<"${out//$'\r'/}"
}

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

refuse_default() {
  local default="" what="'$2'"
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

ACTING=$(gh api --hostname github.com graphql -f 'query=query{viewer{login}}' \
  --jq .data.viewer.login 2>/dev/null | tr -d '\r')
if [[ -n "$PRE_PUSH" ]]; then
  if [[ "$ACTING" == *"[bot]" ]]; then
    echo "push-branch.sh: --preflight is refused in a lane: lane-push.sh is the only way a lane pushes, and it never rewrites a branch" >&2
    exit 1
  fi
  if [[ ! "$ACTING" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
    echo "push-branch.sh: --preflight is refused: the acting login could not be read; not pushing" >&2
    exit 1
  fi
  if [[ -n "$PR" && (-z "${PR_BASE_REPO:-}" || "${HEAD_REPO,,}" != "${PR_BASE_REPO,,}") ]]; then
    echo "push-branch.sh: --preflight is refused: PR '$PR' head is in a fork or its base repository could not be read; not pushing" >&2
    exit 1
  fi
fi
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
  TARGET=(--branch "$BRANCH")
  [[ -z "$PR" ]] || TARGET=(--pr "$PR")
  exec bash "${SCRIPT_DIR}/../../../scripts/lane-push.sh" --dir "$SRC_DIR" --login "$IDENTITY" --repo "$BASE_REPO" "${TARGET[@]}"
fi

if [[ -n "$PRE_PUSH" && -z "$BRANCH" ]]; then
  echo "push-branch.sh: --preflight needs a branch name or --pr (detached HEAD?); not pushing" >&2
  exit 1
fi
PUSH_REMOTE=$(bash "$RESOLVER" --push "$BRANCH") || exit 1
[[ -z "$BRANCH" ]] || refuse_default "$PUSH_REMOTE" "$BRANCH"
URL_TARGET="PR '$PR' head repository '${HEAD_REPO:-}'"
if [[ -n "$PRE_PUSH" && -z "$PR" ]]; then
  HEAD_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null | tr -d '\r')
  if [[ -z "$HEAD_REPO" ]]; then
    echo "push-branch.sh: --preflight is refused: the repository could not be read; not pushing" >&2
    exit 1
  fi
  URL_TARGET="repository '$HEAD_REPO'"
fi
if [[ -n "${HEAD_REPO:-}" ]]; then
  URLS=$(git remote get-url --push --all "$PUSH_REMOTE" 2>/dev/null)
  while IFS= read -r URL; do
    URL_REPO=$(github_repo_of "$URL")
    if [[ -z "$URL_REPO" || "${URL_REPO,,}" != "${HEAD_REPO,,}" ]]; then
      echo "push-branch.sh: '$BRANCH' pushes to '$PUSH_REMOTE' ($URL), not $URL_TARGET on github.com (https://github.com/, ssh://git@github.com/ or git@github.com:); not pushing" >&2
      exit 1
    fi
  done <<<"$URLS"
fi

if [[ -n "$PRE_PUSH" ]]; then
  printf '%s\t%s\n' "$PUSH_REMOTE" "$BRANCH"
  exit 0
fi

FETCH_REMOTE=$(bash "$RESOLVER" "$BRANCH" 2>/dev/null)

sync_skip() { echo "push-branch.sh: sync-stale-base skipped: $1; pushing as is" >&2; }

local_default() {
  local d b
  d=$(git symbolic-ref --short "refs/remotes/$1/HEAD" 2>/dev/null) && { echo "${d#"$1"/}"; return 0; }
  for b in main master trunk; do
    git rev-parse -q --verify "refs/remotes/$1/$b" >/dev/null && { echo "$b"; return 0; }
  done
}

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

sync_stale_base() {
  local wd="$1" on="$SYNC" base="${PR_BASE_REF:-}" base_repo="${PR_BASE_REPO:-}" remote="$FETCH_REMOTE"
  local out err ref r sign=() flags=(--paths-only)
  [[ "$on" != false ]] || return 0
  [[ -z "$base_repo" ]] || remote=$(cd "${wd:-.}" && remote_of_repo "$base_repo")
  if [[ -z "$on" && -z "$PR" ]]; then
    for r in $(cd "${wd:-.}" && git remote); do
      [[ "$(cd "${wd:-.}" && setting_at "$r")" != true ]] || on=pending
    done
    [[ -n "$on" ]] || return 0
  elif [[ -z "$on" ]]; then
    [[ -n "$remote" && "$(cd "${wd:-.}" && setting_at "$remote")" == true ]] || return 0
    on=true
  fi
  [[ -n "$wd" ]] || { sync_skip "'$BRANCH' is checked out in no worktree"; return 0; }
  if [[ -z "$PR" ]]; then
    err=$(mktemp) || return 0
    if out=$(gh pr view "$BRANCH" --json baseRefName,url -q '.baseRefName + " " + (.url | split("/")[3:5] | join("/"))' 2>"$err"); then
      read -r base base_repo <<<"${out//$'\r'/}"
      remote=$(cd "$wd" && remote_of_repo "$base_repo")
    elif grep -q "no pull requests found" "$err"; then
      base=$(cd "$wd" && local_default "$FETCH_REMOTE")
      [[ -n "$base" ]] || base=$(cd "$wd" && remote_default "$FETCH_REMOTE")
    fi
    rm -f "$err"
    if [[ "$on" == pending && -n "$remote" ]]; then
      [[ "$(cd "$wd" && setting_at "$remote")" == true ]] || return 0
    fi
  fi
  [[ -n "$remote" ]] || { sync_skip "no remote fetches the base repository ${base_repo:-of $BRANCH}"; return 0; }
  [[ -n "$base" ]] || { sync_skip "the base branch of '$BRANCH' could not be read"; return 0; }
  ref="$remote/$base"
  git -C "$wd" fetch --quiet "$remote" "+refs/heads/$base:refs/remotes/$ref" || { sync_skip "git fetch of $ref failed"; return 0; }
  git -C "$wd" diff --quiet HEAD -- || { sync_skip "tracked files in $wd have uncommitted edits"; return 0; }
  ! git -C "$wd" rev-parse -q --verify MERGE_HEAD >/dev/null || { sync_skip "a merge is in progress in $wd"; return 0; }
  [[ "$base" != "$(cd "$wd" && remote_default "$remote")" ]] || flags=()
  out=$(bash "$SCRIPT_DIR/../../../scripts/stale-base-overlap.sh" ${flags[@]+"${flags[@]}"} "$wd" "$ref")
  case "$out" in
    yes) ;;
    no) return 0 ;;
    *) sync_skip "${out#unknown }"; return 0 ;;
  esac
  out=$(git -C "$wd" cat-file commit HEAD)
  if [[ "$(git -C "$wd" config --bool commit.gpgsign)" != true && "$out" =~ (^|$'\n')gpgsig(-sha256)?\  ]]; then
    sign=(-S)
  fi
  if git -C "$wd" merge --no-edit --no-stat ${sign[@]+"${sign[@]}"} "$ref" >&2; then
    echo "push-branch.sh: merged $ref into '$BRANCH' (stale base with overlapping paths); HEAD is now $(git -C "$wd" rev-parse HEAD)" >&2
    return 0
  fi
  out=$(git -C "$wd" diff --name-only --diff-filter=U)
  git -C "$wd" merge --abort 2>/dev/null
  if [[ -n "$out" ]]; then
    echo "push-branch.sh: merging $ref into '$BRANCH' conflicted; merge aborted; not pushing. Merge it by hand and resolve the conflicts per /source-control:pull-request's base-merge step (ready-for-review.md §2.5.2), then push again" >&2
    exit 4
  fi
  echo "push-branch.sh: merging $ref into '$BRANCH' failed; not pushing" >&2
  exit 1
}

stale_media_note() {
  local out pr="$PR"
  [[ -n "$1" && -f "$SCRIPT_DIR/media.py" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  [[ -n "$pr" ]] || pr=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty' \
    ${PR_BASE_REPO:+--repo "$PR_BASE_REPO"} 2>/dev/null) || return 0
  [[ "$pr" =~ ^[0-9]+$ ]] || return 0
  out=$(python3 -B "$SCRIPT_DIR/media.py" stale "$pr" --head "$1" --quiet \
    ${PR_BASE_REPO:+--repo "$PR_BASE_REPO"} 2>/dev/null) || return 0
  [[ -z "$out" ]] || echo "push-branch.sh: $out" >&2
}

push_then_note() {
  local sha="$1" rc=0
  shift
  git push "$@" || rc=$?
  ((rc)) || stale_media_note "$sha"
  return "$rc"
}

if [[ -n "$DIR" ]]; then
  sync_stale_base "$(pwd -P)"
  push_then_note "$(git rev-parse HEAD 2>/dev/null)" "$PUSH_REMOTE" "HEAD:refs/heads/$BRANCH"
  exit
fi
[[ -z "$BRANCH" ]] || sync_stale_base "$(worktree_of "$BRANCH")"
PUSHED_SHA=$(git rev-parse --verify --quiet "refs/heads/$BRANCH" 2>/dev/null)
EXISTING_REMOTE=$(git config "branch.${BRANCH}.remote" 2>/dev/null)
EXISTING_MERGE=$(git config "branch.${BRANCH}.merge" 2>/dev/null)

if [[ -z "$EXISTING_REMOTE" && -z "$EXISTING_MERGE" && "$FETCH_REMOTE" == "$PUSH_REMOTE" ]]; then
  push_then_note "$PUSHED_SHA" -u "$PUSH_REMOTE" "$BRANCH"
else
  push_then_note "$PUSHED_SHA" "$PUSH_REMOTE" "$BRANCH"
fi
