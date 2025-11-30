#!/usr/bin/env bash
# log-sessionstart.sh - Log stdin/stdout for SessionStart hook event
#
# Event: SessionStart
# Purpose: Log all SessionStart hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "sessionstart" "$SCRIPT_DIR"
exit 0

