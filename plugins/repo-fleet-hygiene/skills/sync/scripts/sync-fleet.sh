#!/usr/bin/env bash
# Move canonical checkouts onto the remote default branch and fast-forward.
# Bare invocation prints a dry-run plan. Mutation requires --apply and one
# confirmation (--yes, or a single prompt on a terminal).
# Non-fast-forward, dubious ownership, and a partial stash apply are skipped
# and reported. Nothing is reset.
# Parking dirty work needs --worktree-create <path to worktree-create.sh>, the
# only way this script learns of the helper; without it a dirty repo is skipped.
# --worktree-root overrides the root the helper resolves from the repository.
# A skipped line is skipped<TAB>repo<TAB>reason[<TAB>extra]<TAB>git-exit=<n><TAB>remedy=<text>.
# git-exit is the status of the command that failed (the worktree helper's for
# a worktree skip), or none when a plan rule skipped the repo.
# Exit status: 0 when no repo was skipped, 1 when any was, 2 usage, 3 refused.
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
FAILS=0
STASH_SHA=""

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

[[ -z "$WT_CREATE" ]] || [[ -f "$WT_CREATE" && "${WT_CREATE##*/}" == worktree-create.sh ]] ||
  fail "--worktree-create must name an existing file called worktree-create.sh: $WT_CREATE"

[[ -z "$CONFIG" || -f "$CONFIG" ]] || fail "--config file not found: $CONFIG"

# Relative fleet.root and fleet.repo entries resolve against the config file's
# directory, as audit resolves them, never against the caller's cwd.
load_config_scope() {
  [[ -n "$CONFIG" && -f "$CONFIG" ]] || return 0
  local path base
  base="$(cd "$(dirname "$CONFIG")" && pwd)"
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ "$path" == /* ]] || path="$base/$path"
    ROOTS+=("$path")
  done < <(git config --file "$CONFIG" --get-all fleet.root 2>/dev/null || true)
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ "$path" == /* ]] || path="$base/$path"
    REPOS+=("$path")
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

# The same package-manager cache trees audit skips: Cargo, pnpm, and uv keep
# real git checkouts in them, and this verb would switch and pull those.
SKIP_NAMES=(vendor node_modules .venv .pnpm-store .yarn .npm .cargo .rustup .gradle .m2 .nuget __pycache__ .tox)

discover_root() {
  local root="$1" gitdir name
  local prune=()
  [[ -d "$root" ]] || return 0
  for name in "${SKIP_NAMES[@]}"; do
    prune+=(${prune[@]+-o} -name "$name")
  done
  while IFS= read -r gitdir; do
    REPOS+=("$(dirname "$gitdir")")
  done < <(find "$root" -maxdepth 5 \( "${prune[@]}" \) -prune -o -name .git -print 2>/dev/null)
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
  line="$(git -C "$repo" ls-remote --symref origin HEAD 2>/dev/null | head -n 1)" || return $?
  [[ "$line" == ref:\ refs/heads/* ]] || return 1
  ref="${line#ref: }"
  ref="${ref%%$'\t'*}"
  ref="${ref#refs/heads/}"
  # The remote chooses this name and it reaches git as a positional argument,
  # so a leading dash or an invalid ref name is refused.
  [[ -n "$ref" && "$ref" != -* ]] || return 1
  git check-ref-format --branch "$ref" >/dev/null 2>&1 || return 1
  printf '%s\n' "$ref"
}

declare -a PLAN_REPO=() PLAN_ACTION=() PLAN_BRANCH=() PLAN_NOTE=() PLAN_RC=()

# add_plan <repo> <action> <branch> <note> [<git-exit>]
add_plan() {
  PLAN_REPO+=("$1")
  PLAN_ACTION+=("$2")
  PLAN_BRANCH+=("$3")
  PLAN_NOTE+=("$4")
  PLAN_RC+=("${5:-none}")
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
  rc=0
  git -C "$canonical" status --porcelain >/dev/null 2>&1 || rc=$?
  if ((rc)); then
    add_plan "$canonical" skip "" "dubious-or-unreadable" "$rc"
    continue
  fi
  branch="$(default_branch "$canonical")" || rc=$?
  if [[ -z "$branch" ]]; then
    add_plan "$canonical" skip "" "ls-remote" "$rc"
    continue
  fi
  current="$(git -C "$canonical" branch --show-current 2>/dev/null || true)"
  dirty="$(git -C "$canonical" status --porcelain 2>/dev/null || true)"
  if [[ -n "$dirty" && -z "$current" ]]; then
    add_plan "$canonical" skip "" "detached-dirty"
  elif [[ -n "$dirty" && -z "$WT_CREATE" ]]; then
    add_plan "$canonical" skip "" "worktree-create-missing"
  elif [[ -n "$dirty" && "$current" != "$branch" ]]; then
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

# report_skip <repo> <reason> <git-exit|none> <remedy> [<extra column>]
report_skip() {
  local extra=""
  [[ -n "${5:-}" ]] && extra=$'\t'"$5"
  printf 'skipped\t%s\t%s%s\tgit-exit=%s\tremedy=%s\n' "$1" "$2" "$extra" "$3" "$4"
  FAILS=$((FAILS + 1))
}

switch_default() {
  local repo="$1" branch="$2"
  git -C "$repo" fetch --no-tags origin "$branch" >/dev/null 2>&1 || return $?
  git -C "$repo" switch "$branch" >/dev/null 2>&1 && return 0
  git -C "$repo" switch -c "$branch" --track "origin/$branch" >/dev/null 2>&1
}

ff_pull() {
  local repo="$1" branch="$2"
  git -C "$repo" pull --ff-only origin "$branch" >/dev/null 2>&1
}

# The stash stack is shared by every worktree and session of a repository, so
# parked work is addressed by the SHA of its own entry, never by stack position.

# stash_park <repo> <label>: stash the dirty tree under a marker unique to this
# run and repo, and set STASH_SHA to that entry. Fails closed, after reporting
# the skip, unless exactly one entry carries the marker.
stash_park() {
  local repo="$1" marker line found=""
  marker="fleet-sync $2 $(date -u +%Y%m%dT%H%M%SZ) $$"
  STASH_SHA=""
  git -C "$repo" stash push -u -m "$marker" >/dev/null 2>&1 || {
    report_skip "$repo" stash "$?" "git stash push failed; commit or stash the work by hand, then rerun"
    return 1
  }
  while IFS= read -r line; do
    # A stash subject reads "<prefix>: <message>" and a branch name holds no colon.
    [[ "${line#*: }" == "$marker" ]] || continue
    [[ -z "$found" ]] || { found=""; break; }
    found="${line%% *}"
  done < <(git -C "$repo" stash list --format='%H %gs')
  [[ -n "$found" ]] || {
    report_skip "$repo" stash-lookup none "the stash entry '$marker' was not found exactly once, so nothing was applied or dropped; find the work with git -C '$repo' stash list"
    return 1
  }
  STASH_SHA="$found"
}

# stash_drop <repo> <sha>: drop the entry that carries <sha>, found by SHA now
# because its ref moves whenever another session pushes a stash.
stash_drop() {
  local repo="$1" sha="$2" line ref="" n=0
  while IFS= read -r line; do
    [[ "${line%% *}" == "$sha" ]] || continue
    ref="${line#* }"
    n=$((n + 1))
  done < <(git -C "$repo" stash list --format='%H %gd')
  ((n == 1)) && git -C "$repo" stash drop "$ref" >/dev/null 2>&1
}

# unpark <repo> <branch-holding-work> <sha> [<branch-to-return-to>]: undo a park
# that failed before the worktree held the work. Prints restored, or stash-kept
# when the stash could not be applied back, so a lost restore is never silent.
unpark() {
  local repo="$1" held="$2" sha="$3" back="${4:-}"
  if ! { git -C "$repo" switch "$held" >/dev/null 2>&1 && git -C "$repo" stash apply --index "$sha" >/dev/null 2>&1; }; then
    printf 'stash-kept'
    return
  fi
  stash_drop "$repo" "$sha" || printf 'note: %s: stash %s was applied back but could not be dropped; drop it from git stash list by hand\n' "$repo" "$sha" >&2
  if [[ -n "$back" ]]; then
    git -C "$repo" switch "$back" >/dev/null 2>&1 && git -C "$repo" branch -d "$held" >/dev/null 2>&1
  fi
  printf 'restored'
}

# park_finish <action> <repo> <branch> <held> <sha> [<branch-to-return-to>]: put
# the checkout on the default branch, give <held> a linked worktree, and move
# the work (stash <sha>, taken on <held>) into it.
park_finish() {
  local action="$1" repo="$2" branch="$3" held="$4" sha="$5" back="${6:-}" rc wt errf said hint=""
  local args=(--name "$held" --existing-branch --repo-dir "$repo")
  # Without --root the helper resolves the root from the repository itself.
  [[ -z "$WT_ROOT" ]] || args+=(--root "$WT_ROOT")
  switch_default "$repo" "$branch" || {
    rc=$?
    report_skip "$repo" fetch-or-switch "$rc" "git fetch or git switch to $branch failed; check that origin is reachable, then rerun (on stash-kept the work is still in stash $sha)" "$(unpark "$repo" "$held" "$sha" "$back")"
    return
  }
  errf="$(mktemp)"
  wt="$(bash "$WT_CREATE" "${args[@]}" 2>"$errf")"
  rc=$?
  said="$(head -n 1 "$errf" | tr '\t\r' '  ')"
  cat "$errf" >&2
  rm -f "$errf"
  # Helper exit 4 and 5 leave a worktree on disk (worktree-create.sh header): keep it.
  if ! [[ "$rc" =~ ^(0|4|5)$ && -n "$wt" && -d "$wt" ]]; then
    ((rc != 3)) || hint="; set worktreeroot.path in the repository's git config, or pass --worktree-root <dir>"
    report_skip "$repo" worktree "$rc" "worktree-create.sh exited $rc and reported no usable worktree (${said:-no message})$hint; then rerun (on stash-kept the work is still in stash $sha; check git worktree list for a worktree the helper left)" "$(unpark "$repo" "$held" "$sha" "$back")"
    return
  fi
  ((rc == 0)) || printf 'note: %s: worktree-create.sh exited %s but the worktree exists at %s; continuing with the stash apply (its warning is above)\n' "$repo" "$rc" "$wt" >&2
  git -C "$wt" stash apply --index "$sha" >/dev/null 2>&1 || {
    rc=$?
    report_skip "$wt" partial-stash "$rc" "stash $sha did not apply cleanly in $wt and was kept; inspect the worktree, then apply it again from git -C '$repo' stash list"
    return
  }
  stash_drop "$repo" "$sha" || printf 'note: %s: stash %s was applied in %s but could not be dropped; drop it from git stash list by hand\n' "$repo" "$sha" "$wt" >&2
  ff_pull "$repo" "$branch" || {
    report_skip "$repo" non-fast-forward "$?" "git pull --ff-only origin $branch failed after the work moved to $wt; rebase or merge by hand, or check that origin is reachable"
    return
  }
  printf 'applied\t%s\t%s\t%s\n' "$repo" "$action" "$wt"
}

for ((i = 0; i < ${#PLAN_REPO[@]}; i++)); do
  repo="${PLAN_REPO[$i]}"
  action="${PLAN_ACTION[$i]}"
  branch="${PLAN_BRANCH[$i]}"
  note="${PLAN_NOTE[$i]}"
  case "$action" in
  skip)
    case "$note" in
    not-a-directory) remedy="check the path, then fix or remove it in the fleet config or the --repo and --root arguments" ;;
    dubious-or-unreadable) remedy="if git names dubious ownership, run git config --global --add safe.directory '$repo' once you trust its owner; otherwise check that it is a readable git repository" ;;
    ls-remote) remedy="check that origin is reachable and names a default branch: git -C '$repo' ls-remote --symref origin HEAD" ;;
    detached-dirty) remedy="check out a branch or commit the work in '$repo', then rerun" ;;
    worktree-create-missing) remedy="pass --worktree-create <path to source-control's scripts/worktree-create.sh> so the work can be parked, or park it by hand with /source-control:worktree create --existing-branch, or commit or stash it in '$repo'" ;;
    *) remedy="see the reason" ;;
    esac
    report_skip "$repo" "$note" "${PLAN_RC[$i]}" "$remedy"
    ;;
  ff-only | checkout-default)
    switch_default "$repo" "$branch" || {
      report_skip "$repo" fetch-or-switch "$?" "git fetch or git switch to $branch failed; check that origin is reachable, then rerun"
      continue
    }
    ff_pull "$repo" "$branch" || {
      report_skip "$repo" non-fast-forward "$?" "git pull --ff-only origin $branch failed: local commits origin lacks, or origin is unreachable; rebase or merge by hand, nothing was reset"
      continue
    }
    printf 'applied\t%s\t%s\n' "$repo" "$action"
    ;;
  park-existing)
    stash_park "$repo" "$note" || continue
    park_finish park-existing "$repo" "$branch" "$note" "$STASH_SHA"
    ;;
  park-dirty-default)
    park="sync-park/$(date -u +%Y%m%dT%H%M%SZ)"
    git -C "$repo" switch -c "$park" >/dev/null 2>&1 || {
      report_skip "$repo" park-branch "$?" "git switch -c $park failed; check that the checkout is writable and the name is free, then rerun"
      continue
    }
    if ! stash_park "$repo" "$park"; then
      git -C "$repo" switch "$branch" >/dev/null 2>&1 && git -C "$repo" branch -d "$park" >/dev/null 2>&1
      continue
    fi
    park_finish park-dirty-default "$repo" "$branch" "$park" "$STASH_SHA" "$branch"
    ;;
  *)
    report_skip "$repo" unknown-action none "the plan named an action this script does not run; report this as a bug"
    ;;
  esac
done

((FAILS == 0)) || exit 1
exit 0
