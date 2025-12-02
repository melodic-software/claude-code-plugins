#!/usr/bin/env bash
# log-permissionrequest.sh - Log stdin/stdout for PermissionRequest hook event
#
# Event: PermissionRequest
# Purpose: Log all PermissionRequest hook events for observability and troubleshooting

set -euo pipefail

# Get script directory and route through Python logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"
run_python_event_logger "permissionrequest" "$SCRIPT_DIR"
exit 0

