#!/usr/bin/env bash
# Fails a run-claude-cli leg whose CLI init message does not report the
# permission mode asked for. Reads MODE (the requested mode) and
# EXECUTION_FILE (the leg's stream-json array) from the environment.
#
# One mismatch passes: an init mode of default when dontAsk was asked for.
# The launcher sets CLAUDE_CODE_SUBPROCESS_ENV_SCRUB, under which the CLI
# forces the default mode, and it always passes --permission-prompts none,
# under which default denies every call no rule allows, as dontAsk does.
# callers.test.mjs holds the launcher pins checked to pass that flag.
set -euo pipefail

mode=$(jq -r 'if type == "array" then ([.[] | select(.type? == "system" and .subtype? == "init")] | first | .permissionMode // "") else "" end' "${EXECUTION_FILE:-}" 2>/dev/null) || mode=""
if [[ -n ${MODE:-} ]] && { [[ $mode == "$MODE" ]] || [[ $MODE == dontAsk && $mode == default ]]; }; then
  exit 0
fi
echo "::error::permission-mode: the leg's init message does not report the mode asked for (${MODE:-})"
exit 1
