#!/usr/bin/env bash
set -euo pipefail

mode=$(jq -r 'if type == "array" then ([.[] | select(.type? == "system" and .subtype? == "init")] | first | .permissionMode // "") else "" end' "${EXECUTION_FILE:-}" 2>/dev/null) || mode=""
if [[ -n ${MODE:-} ]] && { [[ $mode == "$MODE" ]] || [[ $MODE == dontAsk && $mode == default ]]; }; then
  exit 0
fi
echo "::error::permission-mode: the leg's init message does not report the mode asked for (${MODE:-})"
exit 1
