#!/usr/bin/env bash
# log-precompact.sh - Log stdin/stdout for PreCompact hook event
#
# Event: PreCompact
# Purpose: Log all PreCompact hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "precompact" "$SCRIPT_DIR"
exit 0

