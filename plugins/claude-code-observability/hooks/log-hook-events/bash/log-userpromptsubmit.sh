#!/usr/bin/env bash
# log-userpromptsubmit.sh - Log stdin/stdout for UserPromptSubmit hook event
#
# Event: UserPromptSubmit
# Purpose: Log all UserPromptSubmit hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "userpromptsubmit" "$SCRIPT_DIR"
exit 0

