#!/usr/bin/env bash
# Fabrikam ledger-api: a README whose every claim is true, with no codebase-health config and no docs/ directory.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" clean
