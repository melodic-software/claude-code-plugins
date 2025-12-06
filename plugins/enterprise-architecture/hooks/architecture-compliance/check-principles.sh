#!/usr/bin/env bash
# Architecture compliance check (disabled by default)
# Enable with: CLAUDE_HOOK_ARCHITECTURE_COMPLIANCE_ENABLED=true
#
# This hook provides lightweight architecture compliance checking on file writes.
# For comprehensive validation, use the /ea:architecture-review command.

set -euo pipefail

# Exit early if disabled (default)
# Accepts: true, TRUE, True, 1, yes, YES, Yes (case-insensitive)
ENABLED_LOWER=$(echo "${ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
if [ "$ENABLED_LOWER" != "true" ] && [ "$ENABLED_LOWER" != "1" ] && [ "$ENABLED_LOWER" != "yes" ]; then
    exit 0
fi

# Check if project has architecture principles
PRINCIPLES_FILE="architecture/principles.md"
if [ ! -f "$PRINCIPLES_FILE" ]; then
    # No principles defined, skip check
    exit 0
fi

# Read stdin (tool result)
TOOL_RESULT=$(cat)

# Basic check - just notify that architecture compliance is enabled
# Full validation requires the /ea:architecture-review command which uses
# the principles-validator agent for comprehensive analysis

echo "Architecture compliance check: File modification detected."
echo "Note: For comprehensive validation, run /ea:architecture-review"

# This hook intentionally does minimal work to avoid slowing down edits.
# It serves as a reminder that architecture principles exist and should be considered.
# The heavy lifting is done by the principles-validator agent when explicitly invoked.

exit 0
