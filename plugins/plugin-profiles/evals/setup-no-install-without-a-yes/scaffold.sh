#!/usr/bin/env bash
# fixture-market with notes-hooks installed and draw left uninstalled.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fixture-market.sh" draw-missing
