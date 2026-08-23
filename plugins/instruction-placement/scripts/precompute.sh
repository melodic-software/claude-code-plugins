#!/usr/bin/env bash
# precompute.sh — one-shot orientation facts for this plugin's skill headers.
#
# WHY ONE SCRIPT INSTEAD OF SEVERAL INLINE LINES. A skill whose `## Pre-computed
# context` block runs a git command AND carries more than one inline injection
# line is refused in worktree-isolated agents: CI stays green, ordinary sessions
# render fine, and only the isolated agent fails. Composing every fact into a
# single invocation keeps these skills usable there.
#
# Every probe degrades to a printable value rather than failing, because this
# output is injected into a skill header where a non-zero exit or an error
# stream would land in the model's context as noise.
#
# Usage:
#   precompute.sh audit     surfaces and their sizes, for the sweep
#   precompute.sh realign   branch and working-tree state, for the apply gate
#
# Exit: 0 always on a recognized mode; 2 on a bad argument.

set -uo pipefail

lines_of() {
  if [[ -f "$1" ]]; then
    wc -l <"$1" 2>/dev/null | tr -d ' \r'
  else
    printf 'absent'
  fi
}

count_or_zero() {
  local n
  n="$("$@" 2>/dev/null | wc -l | tr -d ' \r')"
  printf '%s' "${n:-0}"
}

branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\r' || true
}

case "${1:-}" in
audit)
  printf -- '- Branch: %s\n' "$(branch || true)"
  printf -- '- Root CLAUDE.md lines: %s\n' "$(lines_of CLAUDE.md)"
  printf -- '- Root AGENTS.md lines: %s\n' "$(lines_of AGENTS.md)"
  printf -- '- Rules files: %s\n' \
    "$(count_or_zero find .claude/rules -type f -name '*.md')"
  printf -- '- Nested instruction files: %s\n' \
    "$(count_or_zero find . -mindepth 2 \( -name CLAUDE.md -o -name AGENTS.md \) \
      -not -path './.git/*' -not -path './node_modules/*')"
  ;;
realign)
  printf -- '- Branch: %s\n' "$(branch || true)"
  printf -- '- Uncommitted files: %s\n' "$(count_or_zero git status --porcelain)"
  ;;
*)
  printf 'usage: precompute.sh audit|realign\n' >&2
  exit 2
  ;;
esac

exit 0
