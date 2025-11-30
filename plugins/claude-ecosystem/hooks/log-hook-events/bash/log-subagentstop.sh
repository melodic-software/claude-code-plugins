#!/usr/bin/env bash
# log-subagentstop.sh - Log stdin/stdout for SubagentStop hook event
#
# Event: SubagentStop
# Purpose: Log all SubagentStop hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "subagentstop" "$SCRIPT_DIR"
exit 0

