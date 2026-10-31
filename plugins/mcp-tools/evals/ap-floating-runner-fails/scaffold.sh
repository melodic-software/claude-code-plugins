#!/usr/bin/env bash
# Stages the shared MCP config files under configs/.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ap-configs.sh"
