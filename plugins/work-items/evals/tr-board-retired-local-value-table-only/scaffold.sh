#!/usr/bin/env bash
# A local-markdown tracker with two raw items, and the retired $HOME/.claude/rendered-views.md setting terminal.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" board-retired
