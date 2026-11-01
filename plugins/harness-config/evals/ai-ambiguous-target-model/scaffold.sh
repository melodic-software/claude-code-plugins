#!/usr/bin/env bash
# The harbor monorepo with its Claude Code configuration, committed on main.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/harbor-repo.sh"
