#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
[[ "${1:-}" == --end-of-turn ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :
[[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
hook::git_untrusted_env || exit 0
err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/lint.sh" --worktree 2>&1 >/dev/null)" && exit 0
report=""
while IFS= read -r line; do
  case "$line" in
    "FAIL: "*" missing. Install: "* | "To skip only while "*" is missing: "*) ;;
    *) report+="$line"$'\n' ;;
  esac
done <<<"$err"
[[ -n "${report//[[:space:]]/}" ]] || exit 0
printf '%s' "$report" >&2
exit 2
