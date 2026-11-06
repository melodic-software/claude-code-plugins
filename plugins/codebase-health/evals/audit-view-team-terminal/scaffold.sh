#!/usr/bin/env bash
# Fabrikam ledger-api in its own repository: a README naming a missing npm run serve script, and a tracked team rendered-views.yaml setting terminal.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" view-team-terminal
