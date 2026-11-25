#!/usr/bin/env bash
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

default_branch=$(git ls-remote --symref --end-of-options origin HEAD 2>/dev/null |
  awk '/^ref:/{sub(/refs\/heads\//,"",$2); print $2; exit}')

if [[ -n "$default_branch" ]] &&
  git fetch origin "$default_branch" 2>/dev/null &&
  git diff --shortstat FETCH_HEAD...HEAD 2>/dev/null; then
  exit 0
fi

# portability-ok: last rung of a detection-first ladder — reached only after the
git diff --shortstat origin/main...HEAD 2>/dev/null && exit 0

echo "unavailable"
