#!/usr/bin/env bash
# hook-wrapper.sh - Normalize CLAUDE_PLUGIN_ROOT paths for Windows compatibility
#
# Usage: bash ${CLAUDE_PLUGIN_ROOT}/hooks/shared/hook-wrapper.sh <relative-script-path>
# Example: bash ${CLAUDE_PLUGIN_ROOT}/hooks/shared/hook-wrapper.sh /hooks/your-hook/script.sh
#
# Problem: On Windows, CLAUDE_PLUGIN_ROOT uses backslashes (C:\Users\...) but hook
# commands in hooks.json use forward slashes. This creates malformed paths like:
#   C:\Users\...\plugins\your-plugin/hooks/your-hook/script.sh
#
# Solution: This wrapper uses bash's path resolution (cd + pwd) to normalize the
# mixed-separator path into a valid Unix path that bash can execute.
#
# Workaround for: https://github.com/anthropics/claude-code/issues/11984

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "ERROR: Usage: $0 <relative-script-path>" >&2
    echo "Example: $0 /hooks/your-hook/script.sh" >&2
    exit 1
fi

RELATIVE_PATH="$1"

# Get wrapper directory using bash path resolution (handles mixed separators)
# This is the key trick: cd + pwd normalizes Windows paths to Unix format
WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate to plugin root (../../ from hooks/shared)
PLUGIN_ROOT="$(cd "${WRAPPER_DIR}/../.." && pwd)"

# Construct absolute path to target script
TARGET_SCRIPT="${PLUGIN_ROOT}${RELATIVE_PATH}"

# Security: Validate path doesn't escape plugin root (path traversal prevention)
# Use realpath if available to canonicalize and verify containment
if command -v realpath &> /dev/null; then
    CANONICAL_TARGET="$(realpath -m "$TARGET_SCRIPT" 2>/dev/null || echo "$TARGET_SCRIPT")"
    if [[ "$CANONICAL_TARGET" != "${PLUGIN_ROOT}"* ]]; then
        echo "ERROR: Target script escapes plugin root (path traversal blocked)" >&2
        echo "PLUGIN_ROOT: $PLUGIN_ROOT" >&2
        echo "CANONICAL_TARGET: $CANONICAL_TARGET" >&2
        exit 1
    fi
fi

# Verify target script exists
if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "ERROR: Target script not found: $TARGET_SCRIPT" >&2
    echo "PLUGIN_ROOT: $PLUGIN_ROOT" >&2
    echo "RELATIVE_PATH: $RELATIVE_PATH" >&2
    exit 1
fi

# Execute target script with stdin passthrough
# Using exec replaces this process, preserving stdin/stdout/stderr and exit codes
exec bash "$TARGET_SCRIPT"
