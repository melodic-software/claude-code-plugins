#!/usr/bin/env bash
# Fabrikam ledger-api: a README that names an npm run serve script package.json lacks.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" drift
