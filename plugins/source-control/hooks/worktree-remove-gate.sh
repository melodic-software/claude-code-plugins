#!/usr/bin/env bash

set -uo pipefail

_WT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_WT_DIR" == "${BASH_SOURCE[0]}" ]] && _WT_DIR=.
case "$_WT_DIR" in
/* | ?:[/\\]*) HOOK_DIR="$_WT_DIR" ;;
*) HOOK_DIR="$(cd "$_WT_DIR" && pwd)" ;;
esac

gate::refuse() {
  local remedy="$1"
  shift
  printf 'worktree-remove-gate: %s\n' "$remedy" >&2
  local line
  for line in "$@"; do
    printf 'worktree-remove-gate:   %s\n' "$line" >&2
  done
  exit 1
}

command -v jq >/dev/null 2>&1 ||
  gate::refuse 'install jq (https://jqlang.org/download/), then remove the worktree again' \
    'jq reads the WorktreeRemove payload, so the worktree was left on disk'

payload="$(cat)"
[[ -n "$payload" ]] ||
  gate::refuse 'remove the worktree again; if it repeats, run /source-control:worktree cleanup' \
    'nothing arrived on stdin, so there is no worktree_path to act on'

path="$(printf '%s' "$payload" | jq -r '.worktree_path | strings' 2>/dev/null)"
path="${path//$'\r'/}"
session_id="$(printf '%s' "$payload" | jq -r '.session_id | strings' 2>/dev/null)"
session_id="${session_id//$'\r'/}"

[[ -n "$path" ]] ||
  gate::refuse 'run /source-control:worktree cleanup to remove the worktree' \
    'the WorktreeRemove payload carried no worktree_path string'

case "${OSTYPE:-}" in
msys* | cygwin*)
  while [[ ${#path} -gt 1 && ("$path" == */ || "$path" == *\\) ]]; do path="${path%?}"; done
  ;;
*)
  while [[ ${#path} -gt 1 && "$path" == */ ]]; do path="${path%?}"; done
  ;;
esac

case "$path" in
/* | [A-Za-z]:[/\\]*) ;;
*)
  gate::refuse 'run /source-control:worktree cleanup to remove the worktree' \
    "worktree_path is not absolute: $path"
  ;;
esac

[[ -e "$path" || -L "$path" ]] || exit 0

[[ ! -L "$path" ]] ||
  gate::refuse 'check where the link points, then remove it by hand' \
    "worktree_path is a symlink, so it was left in place: $path"
[[ -d "$path" ]] ||
  gate::refuse 'check the path, then remove it by hand' \
    "worktree_path is not a directory: $path"
[[ ! -d "$path/.git" ]] ||
  gate::refuse 'this is a main working tree, never removed by this hook; leave it' \
    "its .git is a directory: $path"
[[ -f "$path/.git" ]] ||
  gate::refuse 'check the directory for work to keep, then remove it by hand' \
    "no .git file, so it is not a linked git worktree and its uncommitted work cannot be checked: $path"

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

git_dirs="$(hook::git_untrusted -C "$path" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)" ||
  gate::refuse 'if the main clone moved, run git worktree repair from it; otherwise check the directory by hand' \
    "git cannot resolve the worktree at $path"
git_dir="${git_dirs%%$'\n'*}"
git_dir="${git_dir%$'\r'}"
common_dir="${git_dirs#*$'\n'}"
common_dir="${common_dir%$'\r'}"
[[ -d "$git_dir" && -d "$common_dir" ]] ||
  gate::refuse 'check the directory by hand, then remove it' \
    "git reported no usable git dir and common dir for $path"
[[ "$git_dir" != "$common_dir" ]] ||
  gate::refuse 'this is a main working tree, never removed by this hook; leave it' \
    "its git dir is its common dir: $path"

for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply sequencer; do
  [[ ! -e "$git_dir/$marker" ]] ||
    gate::refuse 'finish or abort the operation in progress, then remove the worktree again' \
      "$marker exists in $git_dir: an operation is in progress in $path"
done

status="$(hook::git_untrusted -C "$path" status --porcelain --ignore-submodules=none 2>/dev/null)" ||
  gate::refuse 'run git status in the worktree, fix what it reports, then remove it again' \
    "git status failed in $path, so its changes could not be checked"
if [[ -n "$status" ]]; then
  mapfile -t changed <<<"$status"
  gate::refuse 'commit, stash or discard the changes, then remove the worktree again' \
    "${#changed[@]} uncommitted or untracked path(s) in $path, so it was left on disk; first: ${changed[0]}"
fi

[[ ! -e "$path/.gitmodules" && ! -d "$git_dir/modules" ]] ||
  gate::refuse 'remove it with /source-control:worktree cleanup, which confirms before forcing' \
    "$path has submodules, which plain git worktree remove refuses"

if ! hook::git_untrusted -C "$path" symbolic-ref -q HEAD >/dev/null 2>&1; then
  unheld="$(hook::git_untrusted -C "$path" rev-list --max-count=1 HEAD --not --branches --tags --remotes 2>/dev/null)" ||
    gate::refuse 'create a branch at HEAD (git switch -c <name>), then remove the worktree again' \
      "HEAD is detached in $path and its commits could not be checked"
  [[ -z "$unheld" ]] ||
    gate::refuse 'create a branch at HEAD (git switch -c <name>) or push it, then remove the worktree again' \
      "HEAD is detached in $path and holds commits no branch, tag or remote-tracking ref holds"
fi

locked=0
lock_reason=""
if [[ -f "$git_dir/locked" ]]; then
  locked=1
  lock_reason="$(<"$git_dir/locked")"
  lock_reason="${lock_reason//$'\r'/}"
  # shellcheck source=../scripts/lib/worktree-facts.sh
  source "$HOOK_DIR/../scripts/lib/worktree-facts.sh"
  worktree_reason_is_ours "$lock_reason" "$session_id" ||
    gate::refuse 'if the owning session is done, run /source-control:worktree cleanup, which proves the lock stale before unlocking it' \
      "the lock on $path does not name this session (${session_id:-none}): ${lock_reason:-no reason}"
fi

reap="$HOOK_DIR/../scripts/reap-project-plugin-records.sh"
[[ -f "$reap" ]] ||
  gate::refuse 'reinstall or update the source-control plugin; its reap helper is missing' \
    "expected the helper at $reap"
reap_out="$(bash "$reap" --worktree-path "$path" 2>&1)"
reap_rc=$?
if ((reap_rc != 0)); then
  mapfile -t reap_lines <<<"$reap_out"
  gate::refuse 'fix what the reap lines below name, then remove the worktree again, or run /source-control:worktree cleanup' \
    "the reap exited $reap_rc, so $path was left on disk with its records reachable" \
    "${reap_lines[@]}"
fi

cd -- "$common_dir" 2>/dev/null || cd / || true

if ((locked)); then
  unlock_err="$(hook::git_untrusted -C "$common_dir" worktree unlock "$path" 2>&1)" ||
    gate::refuse 'run git worktree unlock on the path, then remove the worktree again' \
      "git worktree unlock failed for $path (its records are already reaped): ${unlock_err//$'\n'/ }"
fi

remove_err="$(hook::git_untrusted -C "$common_dir" worktree remove "$path" 2>&1)"
remove_rc=$?
if ((remove_rc != 0)); then
  if ((locked)) && [[ -e "$path" ]]; then
    hook::git_untrusted -C "$common_dir" worktree lock --reason "$lock_reason" "$path" >/dev/null 2>&1
  fi
  gate::refuse 'fix what the git error below names, then remove the worktree again' \
    "git worktree remove exited $remove_rc for $path (its records are already reaped): ${remove_err//$'\n'/ }"
fi

[[ ! -e "$path" ]] ||
  gate::refuse 'close the process holding a file under the worktree, then delete the directory by hand' \
    "git unregistered the worktree, but $path is still on disk"

exit 0
