#!/usr/bin/env bash
# log-stop.sh - Log stdin/stdout for Stop hook event
#
# Event: Stop
# Purpose: Log all Stop hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "stop" "$SCRIPT_DIR"
exit 0

