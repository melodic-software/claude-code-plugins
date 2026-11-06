#!/usr/bin/env bash
# Seeds the workspace root as the ledger-cli repository, which declares no improvement config in
# any layer: no .claude/improvement.md and no .claude/improvement.local.md.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-ledger-cli.sh"
