#!/usr/bin/env bash
# Stages the shared MCP server sources under servers/.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/au-servers.sh"
