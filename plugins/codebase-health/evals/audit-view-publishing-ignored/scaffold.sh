#!/usr/bin/env bash
# Fabrikam ledger-api in its own repository: a README naming a missing npm run serve script, a tracked team rendered-views.yaml and $HOME/.claude/rendered-views.md both setting artifact.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" view-publishing
