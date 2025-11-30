#!/usr/bin/env bash
# log-notification.sh - Log stdin/stdout for Notification hook event
#
# Event: Notification
# Purpose: Log all Notification hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "notification" "$SCRIPT_DIR"
exit 0

