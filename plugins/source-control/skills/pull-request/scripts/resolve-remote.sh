#!/usr/bin/env bash
# Resolve the git remote a branch should rebase against or push to.
#
# Resolution order:
#   1. branch.<name>.remote, if set and not "." (local-only upstream, e.g. a
#      branch created with `git branch --track . <ref>`)
#   2. `origin`, if configured
#   3. the sole OTHER configured remote — only when exactly one exists
#
# Two or more candidate remotes with neither branch.<name>.remote nor `origin`
# set is ambiguous (e.g. a fork clone with `fork` + `upstream` remotes and no
# `origin`) and fails loudly rather than silently picking one — mirroring the
# failure mode of the hardcoded-`origin` flow this replaces, instead of
# risking a silent rebase/push against the wrong base.
#
# Usage:
#   resolve-remote.sh [branch-name]
#
# With no arg, falls back to `git branch --show-current`. Prints the resolved
# remote name on stdout and exits 0 on success. Exits 1 with a diagnostic on
# stderr when resolution is ambiguous or no remote is configured at all.
set -uo pipefail

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null | tr -d '\r')"
fi

REMOTE=$(git config "branch.${BRANCH}.remote" 2>/dev/null | tr -d '\r')
[[ "$REMOTE" == "." ]] && REMOTE=""

if [[ -z "$REMOTE" ]]; then
  mapfile -t REMOTES < <(git remote)
  if printf '%s\n' "${REMOTES[@]}" | grep -qx origin; then
    REMOTE=origin
  elif [[ ${#REMOTES[@]} -eq 1 ]]; then
    REMOTE="${REMOTES[0]}"
  elif [[ ${#REMOTES[@]} -eq 0 ]]; then
    echo "error: cannot resolve a remote for branch '${BRANCH}': no branch.${BRANCH}.remote is set and no remotes are configured." >&2
    exit 1
  else
    echo "error: cannot resolve a remote for branch '${BRANCH}': no branch.${BRANCH}.remote, no 'origin', and ${#REMOTES[@]} other remotes exist (${REMOTES[*]}). Set branch.${BRANCH}.remote or add an 'origin' remote to disambiguate." >&2
    exit 1
  fi
fi

echo "$REMOTE"
