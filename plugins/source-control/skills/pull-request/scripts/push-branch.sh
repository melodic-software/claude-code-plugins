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
# Usage: push-branch.sh [branch-name]   (defaults to the current branch)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-remote.sh"

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null | tr -d '\r')"
fi

PUSH_REMOTE=$(bash "$RESOLVER" --push "$BRANCH") || exit 1
FETCH_REMOTE=$(bash "$RESOLVER" "$BRANCH" 2>/dev/null)
EXISTING_REMOTE=$(git config "branch.${BRANCH}.remote" 2>/dev/null)
EXISTING_MERGE=$(git config "branch.${BRANCH}.merge" 2>/dev/null)

if [[ -z "$EXISTING_REMOTE" && -z "$EXISTING_MERGE" && "$FETCH_REMOTE" == "$PUSH_REMOTE" ]]; then
  git push -u "$PUSH_REMOTE" "$BRANCH"
else
  git push "$PUSH_REMOTE" "$BRANCH"
fi
