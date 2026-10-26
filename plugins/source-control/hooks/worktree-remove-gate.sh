#!/usr/bin/env bash
# worktree-remove-gate.sh — WorktreeRemove hook: reap the project- and local-scope
# plugin install records of a worktree Claude Code is removing, then remove it.
#
# This plugin's WorktreeCreate hook (worktree-create-gate.sh) creates every
# worktree Claude Code makes, so Claude Code hands their removal to this hook
# instead of running git itself. Removal is the last moment the worktree's
# install records are both identifiable and provably dead, so the reap
# `/source-control:worktree cleanup` runs at its own teardown
# (scripts/reap-project-plugin-records.sh) runs here too.
#
# Contract (hooks page, stamp below):
#   * stdin is one JSON object: the common fields (session_id, cwd, ...) plus
#     `worktree_path`, the path the WorktreeCreate hook returned.
#   * exit 0 counts as removed whatever is left on disk, and no git fallback
#     runs, so this hook deletes the directory itself.
#   * a non-zero exit fails the removal while the directory exists: the worktree
#     stays on disk, and stderr reaches the debug log (and, for a
#     background-session delete, the start of it in agent view). Every refusal
#     leads with the remedy.
#   * it does not fire when a subagent or workflow agent finishes; those
#     worktrees stay for `/source-control:worktree cleanup` and the audit's
#     Step 2b remedy.
#
# Refused before anything is reaped (exit 1, directory left in place):
#   * a path that is relative, a symlink, not a directory, a main working tree,
#     or not a linked worktree git can resolve;
#   * uncommitted or untracked changes, or a merge, rebase, cherry-pick, revert,
#     sequencer or bisect in progress;
#   * submodules, which plain `git worktree remove` refuses;
#   * a detached HEAD holding commits no branch, tag or remote-tracking ref holds;
#   * a lock whose reason does not name the payload's session (any other
#     session's claim, however old, is left for cleanup's stale proof).
# After the guards, a reap that exits non-zero, its exit 3 (no claude CLI, no
# jq, or no enumeration) included, leaves the directory (deleting it would put
# the surviving records out of reach), and so does a failed
# `git worktree remove`; both exit 1, as does a directory still on disk after
# the removal. A path already gone exits 0: there is nothing left to remove.
#
# The worktree's branch is kept: Claude Code never deletes it, and deleting it
# here would destroy commits nothing else holds. Carried gitignored files are not
# compared (`/source-control:pull-request create` owns that sync), and the
# Workspace environment `down` never runs here.
#
# ── Verification stamp (docs/conventions/upstream-drift) ────────────────────────
# Claim: the contract bullets above.
# Basis: <https://code.claude.com/docs/en/hooks#worktreeremove> and
#   <https://code.claude.com/docs/en/hooks#worktreeremove-input>.
# As-of: 2026-10-26.
# Recheck trigger: a Claude Code release note naming WorktreeRemove, or that
#   section changing what an exit code means, the input fields, or which
#   removals fire the event.
# ───────────────────────────────────────────────────────────────────────────────

set -uo pipefail

_WT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_WT_DIR" == "${BASH_SOURCE[0]}" ]] && _WT_DIR=.
case "$_WT_DIR" in
/* | ?:[/\\]*) HOOK_DIR="$_WT_DIR" ;;
*) HOOK_DIR="$(cd "$_WT_DIR" && pwd)" ;;
esac

# Remedy first, diagnosis after: a reader acts on the first line.
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

# Every trailing separator the platform recognizes; off Windows a trailing `\`
# is part of the name.
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

# Already gone: no directory to remove and no record reachable from here; the
# audit's Step 2b reports any records it left.
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

git_dirs="$(git -C "$path" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)" ||
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

status="$(git -C "$path" status --porcelain --ignore-submodules=none 2>/dev/null)" ||
  gate::refuse 'run git status in the worktree, fix what it reports, then remove it again' \
    "git status failed in $path, so its changes could not be checked"
if [[ -n "$status" ]]; then
  mapfile -t changed <<<"$status"
  gate::refuse 'commit, stash or discard the changes, then remove the worktree again' \
    "${#changed[@]} uncommitted or untracked path(s) in $path, so it was left on disk; first: ${changed[0]}"
fi

# Plain `git worktree remove` refuses a worktree with submodules, and the reap
# must not run for a removal that is going to fail.
[[ ! -e "$path/.gitmodules" && ! -d "$git_dir/modules" ]] ||
  gate::refuse 'remove it with /source-control:worktree cleanup, which confirms before forcing' \
    "$path has submodules, which plain git worktree remove refuses"

if ! git -C "$path" symbolic-ref -q HEAD >/dev/null 2>&1; then
  unheld="$(git -C "$path" rev-list --max-count=1 HEAD --not --branches --tags --remotes 2>/dev/null)" ||
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

# Step out of the worktree first: a process whose cwd is inside it holds the
# directory open on Windows.
cd -- "$common_dir" 2>/dev/null || cd / || true

if ((locked)); then
  unlock_err="$(git -C "$common_dir" worktree unlock "$path" 2>&1)" ||
    gate::refuse 'run git worktree unlock on the path, then remove the worktree again' \
      "git worktree unlock failed for $path (its records are already reaped): ${unlock_err//$'\n'/ }"
fi

remove_err="$(git -C "$common_dir" worktree remove "$path" 2>&1)"
remove_rc=$?
if ((remove_rc != 0)); then
  if ((locked)) && [[ -e "$path" ]]; then
    git -C "$common_dir" worktree lock --reason "$lock_reason" "$path" >/dev/null 2>&1
  fi
  gate::refuse 'fix what the git error below names, then remove the worktree again' \
    "git worktree remove exited $remove_rc for $path (its records are already reaped): ${remove_err//$'\n'/ }"
fi

[[ ! -e "$path" ]] ||
  gate::refuse 'close the process holding a file under the worktree, then delete the directory by hand' \
    "git unregistered the worktree, but $path is still on disk"

exit 0
