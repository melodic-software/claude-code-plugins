#!/usr/bin/env bash
set -euo pipefail
work="${PROBE_WORKDIR:?set by probe.py}"
bash "${PROBE_LIB:?set by probe.py}/diverged-repo.sh" "$work"
git -C "$work/repo" worktree add -q "$work/wt-outside" -b outside
