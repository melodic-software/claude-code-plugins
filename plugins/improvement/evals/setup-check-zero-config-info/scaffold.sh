#!/usr/bin/env bash
# Seeds the workspace root as the ledger-cli repository, which declares no improvement config in
# any layer: no docs/conventions/improvement.yaml, no improvement.local.yaml and no old .claude/ file.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-ledger-cli.sh"
