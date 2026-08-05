#!/usr/bin/env bash
# Print `git diff --shortstat` for the committed range between the remote's default
# branch and HEAD, walking a fallback chain until one range resolves.
#
# Why this is a script and not an inline pre-compute line: the fanout skill's
# `## Pre-computed context` block composes its ` !`cmd` ` lines into one shell
# invocation, and the worktree-isolation Bash guard refuses any genuine `$`
# expansion — a `$local` assignment or `$(…)` substitution makes the whole block,
# and therefore the skill, fail to load from an isolated agent (#1687). Plugin
# variables are substituted by the harness into literal paths before a shell sees
# them, so `bash "${CLAUDE_PLUGIN_ROOT}/…/diff-vs-base.sh"` is guard-safe while the
# same logic inline is not. Inside this file `$` is free.
#
# Usage (from anywhere inside the target repository — the caller's cwd is the repo):
#   bash "${CLAUDE_PLUGIN_ROOT}/skills/fanout/scripts/diff-vs-base.sh"
#
# Output: one `git diff --shortstat` line on stdout, or `unavailable` when no
# candidate base resolves. A range that resolves but is empty prints NOTHING —
# `git diff` exits 0 with no output when there is no difference, and the caller
# must be able to tell "no committed changes" from "no base to compare against".
#
# Exit code is 0 on every path, including `unavailable`, so the call site's
# `|| echo "unavailable"` fires only when this file is missing or unreadable.

# `set -e` omitted deliberately: the fallback chain advances on non-zero exit from
# each `git diff` attempt, and `set -e` would abort at the first one.
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
diff-vs-base.sh — print `git diff --shortstat` for HEAD vs the remote's default branch.

Usage:
  diff-vs-base.sh [--help]

Operates on the current repository (cwd) and walks a fallback chain of candidate
base refs, so it may fetch the remote's default branch as a side effect.

Prints the first `--shortstat` line that resolves; nothing when a range resolves
but is empty; `unavailable` when none does. Always exits 0.
EOF
  exit 0
fi

git diff --shortstat origin/HEAD...HEAD 2>/dev/null && exit 0

# The remote's own symbolic HEAD, for clones whose refs/remotes/origin/HEAD was
# never set locally. The fetch is a pre-existing side effect of this probe: it is
# what makes FETCH_HEAD point at the default branch.
default_branch=$(git ls-remote --symref --end-of-options origin HEAD 2>/dev/null |
  awk '/^ref:/{sub(/refs\/heads\//,"",$2); print $2; exit}')

if [[ -n "$default_branch" ]] &&
  git fetch origin "$default_branch" 2>/dev/null &&
  git diff --shortstat FETCH_HEAD...HEAD 2>/dev/null; then
  exit 0
fi

# portability-ok: last rung of a detection-first ladder — reached only after the
# origin/HEAD range and the `git ls-remote --symref` resolution above have both
# failed, which is the split-across-lines shape the branch-coupling gate exempts
# per-site rather than by co-located evidence.
git diff --shortstat origin/main...HEAD 2>/dev/null && exit 0

echo "unavailable"
