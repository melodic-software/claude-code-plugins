#!/usr/bin/env bash
# log-sessionend.sh - Log stdin/stdout for SessionEnd hook event
#
# Event: SessionEnd
# Purpose: Log all SessionEnd hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "sessionend" "$SCRIPT_DIR"
exit 0

