#!/usr/bin/env bash
# Fabrikam ledger-api in its own repository: a README naming a missing npm run serve script, and $HOME/.claude/rendered-views.md setting terminal.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" view-retired-terminal
