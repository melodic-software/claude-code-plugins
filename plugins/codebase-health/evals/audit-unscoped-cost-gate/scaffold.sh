#!/usr/bin/env bash
# Fabrikam ledger-api: a clean README plus 32 topic pages under docs/.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" docs-tree
