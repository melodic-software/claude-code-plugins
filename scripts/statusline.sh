#!/usr/bin/env bash
# Status line script with tiered fallback for performance
# Receives JSON via stdin from Claude Code status line system
#
# NOTE: As of 2025-12-11, external statusline scripts are not being invoked
# due to Claude Code bug #13517. The inline command in .claude/settings.json
# is used instead:
#   "command": "bun x ccusage statusline --visual-burn-rate emoji ..."
#
# This script is kept for reference and future use when the bug is fixed.
# See: https://github.com/anthropics/claude-code/issues/13517

# Common ccusage args
CCUSAGE_ARGS="statusline --visual-burn-rate emoji --context-low-threshold 50 --context-medium-threshold 80 --cost-source auto --no-offline"

# Tier 1: Global ccusage (fastest - no package resolution)
if command -v ccusage &>/dev/null; then
    ccusage $CCUSAGE_ARGS
    exit $?
fi

# Tier 2: bun x ccusage (fast - cached after first run)
if command -v bun &>/dev/null; then
    bun x ccusage $CCUSAGE_ARGS
    exit $?
fi

# Tier 3: Fallback - basic status line
# Read stdin only if we need to parse it (avoid unnecessary read in fast paths)
input=$(cat)

if command -v jq &>/dev/null; then
    MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
    COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
    printf "[%s] \$%.2f (install bun for enhanced status)\n" "$MODEL" "$COST"
else
    echo "[Claude] (install bun for enhanced status)"
fi
