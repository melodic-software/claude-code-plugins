#!/usr/bin/env bash
# Seeds the workspace root as the ledger-cli repository.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-ledger-cli.sh"
