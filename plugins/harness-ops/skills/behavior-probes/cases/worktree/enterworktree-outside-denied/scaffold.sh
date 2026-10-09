#!/usr/bin/env bash
set -euo pipefail
bash "$PROBE_LIB/diverged-repo.sh" "$PROBE_WORKDIR"
git -C "$PROBE_WORKDIR/repo" worktree add -q "$PROBE_WORKDIR/wt-outside" -b outside
