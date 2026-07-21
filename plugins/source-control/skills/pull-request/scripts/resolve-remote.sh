#!/usr/bin/env bash
# Resolve the git remote a branch should fetch/rebase against, or — with
# --push — publish to.
#
# Fetch/rebase resolution order:
#   1. branch.<name>.remote, if set and not "." (local-only upstream, e.g. a
#      branch created with `git branch --track . <ref>`)
#   2. `origin`, if configured
#   3. the sole OTHER configured remote — only when exactly one exists
#
# Push resolution (--push) prepends Git's documented push precedence
# (git-config(1) `remote.pushDefault` / `branch.<name>.pushRemote`,
# git-push(1) "Named Remotes") ahead of that order, because the push
# destination can legitimately differ from the fetch remote in a triangular
# fork flow:
#   1. branch.<name>.pushRemote, if set and not "." (local repo)
#   2. remote.pushDefault, if set and not "." (local repo)
#   3. …then the fetch order above (branch.<name>.remote -> origin -> sole other)
# So a branch tracking `upstream` for fetch (branch.<name>.remote=upstream, as
# `git checkout -b feature upstream/main` sets) but configured to push to a
# fork via `branch.feature.pushRemote=origin` or `remote.pushDefault=origin`
# resolves the push to the fork, not upstream.
#
# Two or more candidate remotes with no way to disambiguate (neither the
# mode's configured remote nor `origin`) is ambiguous (e.g. a fork clone with
# `fork` + `upstream` remotes and no `origin`) and fails loudly rather than
# silently picking one — mirroring the failure mode of the hardcoded-`origin`
# flow this replaces, instead of risking a silent rebase/push against the wrong
# base.
#
# Usage:
#   resolve-remote.sh [--push] [branch-name]
#
# With no branch arg, falls back to `git branch --show-current`. Prints the
# resolved remote name on stdout and exits 0 on success. Exits 1 with a
# diagnostic on stderr when resolution is ambiguous or no remote is configured
# at all.
set -uo pipefail

PUSH=0
if [[ "${1:-}" == "--push" ]]; then
  PUSH=1
  shift
fi

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null | tr -d '\r')"
fi

REMOTE=""
if [[ $PUSH -eq 1 ]]; then
  # Push precedence, ahead of the shared fetch order: branch.<name>.pushRemote
  # overrides remote.pushDefault, which overrides branch.<name>.remote for the
  # push destination. A "." value names the local repo, not a publish target,
  # so it is treated as unset and falls through.
  REMOTE=$(git config "branch.${BRANCH}.pushRemote" 2>/dev/null | tr -d '\r')
  [[ "$REMOTE" == "." ]] && REMOTE=""
  if [[ -z "$REMOTE" ]]; then
    REMOTE=$(git config "remote.pushDefault" 2>/dev/null | tr -d '\r')
    [[ "$REMOTE" == "." ]] && REMOTE=""
  fi
fi

if [[ -z "$REMOTE" ]]; then
  REMOTE=$(git config "branch.${BRANCH}.remote" 2>/dev/null | tr -d '\r')
  [[ "$REMOTE" == "." ]] && REMOTE=""
fi

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
    hint="Set branch.${BRANCH}.remote or add an 'origin' remote to disambiguate."
    [[ $PUSH -eq 1 ]] && hint="Set branch.${BRANCH}.pushRemote or remote.pushDefault (the push destination), or branch.${BRANCH}.remote, or add an 'origin' remote to disambiguate."
    echo "error: cannot resolve a remote for branch '${BRANCH}': no branch.${BRANCH}.remote, no 'origin', and ${#REMOTES[@]} other remotes exist (${REMOTES[*]}). ${hint}" >&2
    exit 1
  fi
fi

echo "$REMOTE"
