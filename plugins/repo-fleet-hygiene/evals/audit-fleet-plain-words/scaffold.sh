#!/usr/bin/env bash
# Two made-up checkouts under ./fleet with local bare remotes, an ancestry-merged branch and a
# linked worktree whose directory is gone.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fleet-repos.sh" audit
