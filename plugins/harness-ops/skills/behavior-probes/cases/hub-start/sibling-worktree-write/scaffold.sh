#!/usr/bin/env bash
set -euo pipefail
w="${PROBE_WORKDIR:?set by probe.py}"
bash "${PROBE_LIB:?set by probe.py}/hub-layout.sh" "$w"
git -C "$w/repos/github.com/acme/target" worktree add -q -b probe/work "$w/worktrees/acme-target-probe"
