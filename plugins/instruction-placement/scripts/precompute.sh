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
# WHY THE COUNTS COME FROM discover.sh. Orientation that disagrees with the
# engine is worse than no orientation: a header reading "Rules files: 1" over a
# repository the check gate walks three rules in reads as "there is barely
# anything here" and sets the wrong expectation before any work starts. The
# open-coded `find .claude/rules` these lines used to run is the exact line
# whose four bugs motivated the shared layer — it sees only the root tree and
# only real directories, so a nested `packages/*/.claude/rules` and a symlinked
# rule set are both invisible to it. Counting through the same functions the
# engines use is what keeps the header and the gate telling one story.
#
# Usage:
#   precompute.sh audit     surfaces and their sizes, for the sweep
#   precompute.sh check     rules count and index-target presence, for the gate
#   precompute.sh realign   branch and working-tree state, for the apply gate
#
# Exit: 0 always on a recognized mode; 2 on a bad argument.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/discover.sh
. "$SCRIPT_DIR/lib/discover.sh"

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

present_or_absent() {
  if [[ -f "$1" ]]; then printf 'present'; else printf 'absent'; fi
}

case "${1:-}" in
audit)
  printf -- '- Branch: %s\n' "$(branch)"
  printf -- '- Root CLAUDE.md lines: %s\n' "$(lines_of CLAUDE.md)"
  printf -- '- Root AGENTS.md lines: %s\n' "$(lines_of AGENTS.md)"
  printf -- '- Rules files: %s\n' "$(count_or_zero ip_discover_rules .)"
  printf -- '- Nested instruction files: %s\n' \
    "$(count_or_zero ip_discover_nested_instructions .)"
  ;;
check)
  printf -- '- Rules files: %s\n' "$(count_or_zero ip_discover_rules .)"
  printf -- '- Root AGENTS.md: %s\n' "$(present_or_absent AGENTS.md)"
  printf -- '- Root CLAUDE.md: %s\n' "$(present_or_absent CLAUDE.md)"
  ;;
realign)
  printf -- '- Branch: %s\n' "$(branch)"
  printf -- '- Uncommitted files: %s\n' "$(count_or_zero git status --porcelain)"
  ;;
*)
  printf 'usage: precompute.sh audit|check|realign\n' >&2
  exit 2
  ;;
esac

exit 0
