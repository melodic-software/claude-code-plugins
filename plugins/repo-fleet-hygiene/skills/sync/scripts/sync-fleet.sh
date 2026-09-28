#!/usr/bin/env bash
# Move canonical checkouts onto the remote default branch and fast-forward.
# Bare invocation prints a dry-run plan. Mutation requires --apply and one
# confirmation (--yes, or a single prompt on a terminal).
# Non-fast-forward, dubious ownership, and a partial stash apply are skipped
# and reported. Nothing is reset.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/scope-resolve.sh
source "$SCRIPT_DIR/../../../scripts/scope-resolve.sh"

REPOS=()
ROOTS=()
NAMED=()
CONFIG=""
PROJECT_DIR=""
APPLY=0
YES=0
WT_ROOT=""
WT_CREATE=""

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo)
    [[ $# -ge 2 && -n "$2" ]] || fail "--repo requires a directory"
    REPOS+=("$2")
    shift 2
    ;;
  --root)
    [[ $# -ge 2 && -n "$2" ]] || fail "--root requires a directory"
    ROOTS+=("$2")
    shift 2
    ;;
  --named)
    [[ $# -ge 2 && -n "$2" ]] || fail "--named requires a directory"
    NAMED+=("$2")
    shift 2
    ;;
  --config)
    [[ $# -ge 2 && -n "$2" ]] || fail "--config requires a file"
    CONFIG="$2"
    shift 2
    ;;
  --project-dir)
    [[ $# -ge 2 && -n "$2" ]] || fail "--project-dir requires a directory"
    PROJECT_DIR="$2"
    shift 2
    ;;
  --apply) APPLY=1; shift ;;
  --yes) YES=1; shift ;;
  --worktree-root)
    [[ $# -ge 2 && -n "$2" ]] || fail "--worktree-root requires a directory"
    WT_ROOT="$2"
    shift 2
    ;;
  --worktree-create)
    [[ $# -ge 2 && -n "$2" ]] || fail "--worktree-create requires a path"
    WT_CREATE="$2"
    shift 2
    ;;
  -*) fail "unknown argument: $1" ;;
  *)
    [[ -n "$1" ]] || fail "bare path requires a directory"
    ROOTS+=("$1")
    shift
    ;;
  esac
done

if [[ -z "$WT_CREATE" ]]; then
  sibling="${SCRIPT_DIR}/../../../../source-control/scripts/worktree-create.sh"
  if [[ -f "$sibling" ]]; then
    WT_CREATE="$sibling"
  fi
fi

load_config_scope() {
  [[ -n "$CONFIG" && -f "$CONFIG" ]] || return 0
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] && ROOTS+=("$path")
  done < <(git config --file "$CONFIG" --get-all fleet.root 2>/dev/null || true)
  while IFS= read -r path; do
    [[ -n "$path" ]] && REPOS+=("$path")
  done < <(git config --file "$CONFIG" --get-all fleet.repo 2>/dev/null || true)
}

if [[ ${#REPOS[@]} -eq 0 && ${#ROOTS[@]} -eq 0 ]]; then
  if [[ -z "$CONFIG" && -n "$PROJECT_DIR" && -f "$PROJECT_DIR/.claude/repo-fleet-hygiene.conf" ]]; then
    CONFIG="$PROJECT_DIR/.claude/repo-fleet-hygiene.conf"
  elif [[ -z "$CONFIG" && -f "${HOME:-}/.claude/repo-fleet-hygiene.conf" ]]; then
    CONFIG="${HOME}/.claude/repo-fleet-hygiene.conf"
  fi
  load_config_scope
fi

if [[ ${#REPOS[@]} -eq 0 && ${#ROOTS[@]} -eq 0 ]]; then
  fallback="$(mktemp)"
  if ! scope_resolve_fallback "${NAMED[@]}" >"$fallback"; then
    rm -f "$fallback"
    cat >&2 <<EOF
Error: no scope resolved.
Tried explicit --repo/--root, fleet config, --named paths, ghq root, and the working directory.
EOF
    exit 3
  fi
  while IFS=$'\t' read -r kind value || [[ -n "${kind:-}" ]]; do
    case "$kind" in
    repo) REPOS+=("$value") ;;
    root) ROOTS+=("$value") ;;
    *) ;;
    esac
  done <"$fallback"
  rm -f "$fallback"
fi

discover_root() {
  local root="$1" gitdir base
  [[ -d "$root" ]] || return 0
  while IFS= read -r gitdir; do
    base="$(dirname "$gitdir")"
    case "$base" in
    */node_modules/* | */vendor/* | */.venv/*) continue ;;
    *) ;;
    esac
    REPOS+=("$base")
  done < <(find "$root" -maxdepth 5 \( -name node_modules -o -name vendor -o -name .venv \) -prune -o -name .git -print 2>/dev/null)
}

for root in "${ROOTS[@]}"; do
  discover_root "$root"
done

main_worktree() {
  local dir="$1" record
  IFS= read -r -d '' record < <(git -C "$dir" worktree list --porcelain -z 2>/dev/null) || return 1
  [[ "$record" == worktree\ * ]] || return 1
  printf '%s\n' "${record#worktree }"
}

default_branch() {
  local repo="$1" line ref
  line="$(git -C "$repo" ls-remote --symref origin HEAD 2>/dev/null | head -n 1)" || return 1
  [[ "$line" == ref:\ refs/heads/* ]] || return 1
  ref="${line#ref: }"
  ref="${ref%%$'\t'*}"
  ref="${ref#refs/heads/}"
  [[ -n "$ref" ]] || return 1
  printf '%s\n' "$ref"
}

declare -a PLAN_REPO=() PLAN_ACTION=() PLAN_BRANCH=() PLAN_NOTE=()

add_plan() {
  PLAN_REPO+=("$1")
  PLAN_ACTION+=("$2")
  PLAN_BRANCH+=("$3")
  PLAN_NOTE+=("$4")
}

seen=""
for repo in "${REPOS[@]}"; do
  [[ -d "$repo" ]] || { add_plan "$repo" skip "" "not-a-directory"; continue; }
  canonical="$(main_worktree "$repo" 2>/dev/null || true)"
  [[ -n "$canonical" ]] || canonical="$repo"
  case " $seen " in
  *" $canonical "*) continue ;;
  *) ;;
  esac
  seen="$seen $canonical"
  if ! git -C "$canonical" status --porcelain >/dev/null 2>&1; then
    add_plan "$canonical" skip "" "dubious-or-unreadable"
    continue
  fi
  branch="$(default_branch "$canonical" || true)"
  if [[ -z "$branch" ]]; then
    add_plan "$canonical" skip "" "ls-remote"
    continue
  fi
  current="$(git -C "$canonical" branch --show-current 2>/dev/null || true)"
  dirty="$(git -C "$canonical" status --porcelain 2>/dev/null || true)"
  if [[ -n "$dirty" && "$current" != "$branch" ]]; then
    add_plan "$canonical" park-existing "$branch" "$current"
  elif [[ -n "$dirty" ]]; then
    add_plan "$canonical" park-dirty-default "$branch" ""
  elif [[ "$current" != "$branch" ]]; then
    add_plan "$canonical" checkout-default "$branch" "$current"
  else
    add_plan "$canonical" ff-only "$branch" ""
  fi
done

printf 'mode: %s\n' "$([[ "$APPLY" -eq 1 ]] && printf apply || printf dry-run)"
printf 'repos: %s\n' "${#PLAN_REPO[@]}"
for ((i = 0; i < ${#PLAN_REPO[@]}; i++)); do
  printf '%s\t%s\t%s\t%s\n' "${PLAN_ACTION[$i]}" "${PLAN_REPO[$i]}" "${PLAN_BRANCH[$i]}" "${PLAN_NOTE[$i]}"
done

[[ "$APPLY" -eq 1 ]] || exit 0

if [[ "$YES" -ne 1 ]]; then
  if [[ ! -t 0 ]]; then
    printf 'Error: --apply on a non-interactive shell requires --yes. Nothing was changed.\n' >&2
    exit 3
  fi
  printf 'Apply this sync plan? [y/N] ' >&2
  read -r answer || answer=""
  case "$answer" in
  y | Y) ;;
  *) printf 'declined\n' >&2; exit 3 ;;
  esac
fi

switch_default() {
  local repo="$1" branch="$2"
  git -C "$repo" fetch --no-tags origin "$branch" >/dev/null 2>&1 || return 1
  git -C "$repo" switch "$branch" >/dev/null 2>&1 && return 0
  git -C "$repo" switch -c "$branch" --track "origin/$branch" >/dev/null 2>&1
}

ff_pull() {
  local repo="$1" branch="$2"
  git -C "$repo" pull --ff-only origin "$branch" >/dev/null 2>&1
}

for ((i = 0; i < ${#PLAN_REPO[@]}; i++)); do
  repo="${PLAN_REPO[$i]}"
  action="${PLAN_ACTION[$i]}"
  branch="${PLAN_BRANCH[$i]}"
  note="${PLAN_NOTE[$i]}"
  case "$action" in
  skip)
    printf 'skipped\t%s\t%s\n' "$repo" "$note"
    ;;
  ff-only | checkout-default)
    if ! switch_default "$repo" "$branch"; then
      printf 'skipped\t%s\tfetch-or-switch\n' "$repo"
      continue
    fi
    if ! ff_pull "$repo" "$branch"; then
      printf 'skipped\t%s\tnon-fast-forward\n' "$repo"
      continue
    fi
    printf 'applied\t%s\t%s\n' "$repo" "$action"
    ;;
  park-existing)
    old="$note"
    if ! git -C "$repo" stash push -u -m "fleet-sync $old" >/dev/null 2>&1; then
      printf 'skipped\t%s\tstash\n' "$repo"
      continue
    fi
    if ! switch_default "$repo" "$branch"; then
      printf 'skipped\t%s\tfetch-or-switch\n' "$repo"
      continue
    fi
    if [[ -z "$WT_CREATE" || -z "$WT_ROOT" ]]; then
      printf 'skipped\t%s\tworktree-create-missing\n' "$repo"
      continue
    fi
    if ! wt="$(bash "$WT_CREATE" --name "$old" --existing-branch --root "$WT_ROOT" --repo-dir "$repo")"; then
      printf 'skipped\t%s\tworktree\n' "$repo"
      continue
    fi
    if ! git -C "$wt" stash apply >/dev/null 2>&1; then
      printf 'skipped\t%s\tpartial-stash\n' "$wt"
      continue
    fi
    git -C "$repo" stash drop >/dev/null 2>&1 || true
    if ! ff_pull "$repo" "$branch"; then
      printf 'skipped\t%s\tnon-fast-forward\n' "$repo"
      continue
    fi
    printf 'applied\t%s\tpark-existing\t%s\n' "$repo" "$wt"
    ;;
  park-dirty-default)
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    park="sync-park/$stamp"
    if ! git -C "$repo" switch -c "$park" >/dev/null 2>&1; then
      printf 'skipped\t%s\tpark-branch\n' "$repo"
      continue
    fi
    if ! git -C "$repo" stash push -u -m "fleet-sync $park" >/dev/null 2>&1; then
      printf 'skipped\t%s\tstash\n' "$repo"
      continue
    fi
    if ! switch_default "$repo" "$branch"; then
      printf 'skipped\t%s\tfetch-or-switch\n' "$repo"
      continue
    fi
    if [[ -z "$WT_CREATE" || -z "$WT_ROOT" ]]; then
      printf 'skipped\t%s\tworktree-create-missing\n' "$repo"
      continue
    fi
    if ! wt="$(bash "$WT_CREATE" --name "$park" --existing-branch --root "$WT_ROOT" --repo-dir "$repo")"; then
      printf 'skipped\t%s\tworktree\n' "$repo"
      continue
    fi
    if ! git -C "$wt" stash apply >/dev/null 2>&1; then
      printf 'skipped\t%s\tpartial-stash\n' "$wt"
      continue
    fi
    git -C "$repo" stash drop >/dev/null 2>&1 || true
    if ! ff_pull "$repo" "$branch"; then
      printf 'skipped\t%s\tnon-fast-forward\n' "$repo"
      continue
    fi
    printf 'applied\t%s\tpark-dirty-default\t%s\n' "$repo" "$wt"
    ;;
  *)
    printf 'skipped\t%s\tunknown-action\n' "$repo"
    ;;
  esac
done
