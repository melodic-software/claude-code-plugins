#!/usr/bin/env bash
# log-pretooluse.sh - Log stdin/stdout for PreToolUse hook event
#
# Event: PreToolUse
# Purpose: Log all PreToolUse hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "pretooluse" "$SCRIPT_DIR"
exit 0

