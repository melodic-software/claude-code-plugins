#!/usr/bin/env bash
# Fabrikam ledger-api: a clean README plus .claude/settings.json and .mcp.json.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" harness
