#!/usr/bin/env bash
# log-posttooluse.sh - Log stdin/stdout for PostToolUse hook event
#
# Event: PostToolUse
# Purpose: Log all PostToolUse hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "posttooluse" "$SCRIPT_DIR"
exit 0

