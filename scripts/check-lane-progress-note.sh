#!/usr/bin/env bash
# The issue lane's progress note must not reach a merge.
#
#   scripts/check-lane-progress-note.sh --check
#       fails when the working tree holds .lane-progress.md, the note a
#       work-resolve-issue run keeps so the next job of a long run resumes
#       with its context. A run that finishes removes it; this check is in
#       the resolve-issue activity's checks, so a done run that left it opens
#       no PR.
#
# Runs from the repository root, or from CHECK_DATA_ROOT when the runner sets it.
set -euo pipefail

if [ "${1:-}" != "--check" ]; then
  echo "usage: scripts/check-lane-progress-note.sh --check" >&2
  exit 2
fi

root=${CHECK_DATA_ROOT:-.}
if [ -e "$root/.lane-progress.md" ] || [ -L "$root/.lane-progress.md" ]; then
  echo "check-lane-progress-note: .lane-progress.md is still in the tree; a finished run removes it" >&2
  exit 1
fi
echo "check-lane-progress-note: no progress note in the tree"
