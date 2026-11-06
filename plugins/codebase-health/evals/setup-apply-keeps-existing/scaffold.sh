#!/usr/bin/env bash
# Fabrikam ledger-api in its own repository, with contracts/ and a committed .claude/codebase-health.md holding a custom api-contracts dimension.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" setup-existing
