#!/usr/bin/env bash
# orders-portal with two linked worktrees under .worktrees/ for merged spike branches.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fabrikam-repo.sh" worktree
