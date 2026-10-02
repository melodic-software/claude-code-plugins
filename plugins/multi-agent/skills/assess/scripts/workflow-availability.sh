#!/usr/bin/env bash
# workflow-availability.sh [--root <dir>] [--home <dir>]
# Read-only. Prints TSV rows `check<TAB>state<TAB>detail` for the switches that
# turn workflows off, then `verdict<TAB>off|not-off`. `not-off` means no switch
# here is set; whether the Workflow tool is in the session's toolset is a
# separate check only the session can make, and managed settings show up there.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
USER_HOME_DIR="${HOME:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --root | --home)
    [[ $# -gt 1 ]] || {
      echo "workflow-availability: $1 needs a directory" >&2
      exit 2
    }
    [[ "$1" == --root ]] && ROOT="$2" || USER_HOME_DIR="$2"
    shift
    ;;
  *)
    echo "workflow-availability: unknown argument '$1'" >&2
    exit 2
    ;;
  esac
  shift
done

off=0
if [[ "${CLAUDE_CODE_DISABLE_WORKFLOWS:-}" == 1 ]]; then
  printf 'env CLAUDE_CODE_DISABLE_WORKFLOWS\toff\tset to 1\n'
  off=1
else
  printf 'env CLAUDE_CODE_DISABLE_WORKFLOWS\tnot-set\t\n'
fi

for f in "$USER_HOME_DIR/.claude/settings.json" "$ROOT/.claude/settings.json" "$ROOT/.claude/settings.local.json"; do
  if [[ ! -f "$f" ]]; then
    printf 'settings disableWorkflows\tabsent\t%s\n' "$f"
  elif grep -qE '"disableWorkflows"[[:space:]]*:[[:space:]]*true' "$f"; then
    printf 'settings disableWorkflows\toff\t%s\n' "$f"
    off=1
  else
    printf 'settings disableWorkflows\tnot-set\t%s\n' "$f"
  fi
done

((off)) && printf 'verdict\toff\n' || printf 'verdict\tnot-off\n'
