#!/usr/bin/env bash

set -uo pipefail

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
[[ "${CLAUDE_PLUGIN_OPTION_SPELLING_ENABLED:-true}" == "true" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

if [[ "${1:-}" == --end-of-turn ]]; then
  hook::buffer_stdin_to INPUT || exit 0
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  command -v typos >/dev/null 2>&1 || exit 0
  hook::git_untrusted_env || exit 0
  "${BASH:-bash}" "$HOOK_DIR/../git-hooks/lint.sh" --worktree >/dev/null || exit 2
fi

exit 0
