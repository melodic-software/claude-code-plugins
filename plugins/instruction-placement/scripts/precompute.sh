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
# anything here" and sets the wrong expectation before any work starts. An
# open-coded `find .claude/rules` sees only the root tree and only real
# directories, so a nested `packages/*/.claude/rules` and a symlinked
# rule set are both invisible to it. Counting through the same functions the
# engines use is what keeps the header and the gate telling one story.
#
# WHY audit AND realign CARRY A MECHANICS LINE. Both price proposals from
# context/verified-mechanics.md, whose first-party measurements each name the
# Claude Code version they ran on, and those mechanics move between releases.
# The record's own recheck trigger (the CLI moving past the measured version)
# fired on 2.1.288, twenty versions past the 2.1.268 it named, and nobody
# noticed, because nothing compared the two. The line compares them every run:
# STALE when the installed CLI is newer than the newest measurement, so the
# skill says so at the top of its output instead of pricing on an unaged
# record. Any newer version counts, the third component included, because
# Claude Code changes loading behavior in releases that move only that
# component. delta and setup share the audit mode, so their headers carry the
# line too.
#
# Usage:
#   precompute.sh audit     surfaces and their sizes, for the sweep
#   precompute.sh check     rules count and index-target presence, for the gate
#   precompute.sh realign   branch and working-tree state, for the apply gate
#
# Env (the test seam; neither is needed in normal use):
#   IP_CLAUDE_BIN          claude binary whose --version is compared
#                          (default: claude on PATH)
#   IP_MECHANICS_RECORD    the record whose measured-on stamps are read
#                          (default: ../context/verified-mechanics.md)
#
# Exit: 0 always on a recognized mode; 2 on a bad argument.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/discover.sh
. "$SCRIPT_DIR/lib/discover.sh"
# shellcheck source=lib/version.sh
. "$SCRIPT_DIR/lib/version.sh"

MECHANICS_RECORD="${IP_MECHANICS_RECORD:-$SCRIPT_DIR/../context/verified-mechanics.md}"

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

installed_cli_version() {
  local bin="${IP_CLAUDE_BIN:-claude}" raw
  command -v "$bin" >/dev/null 2>&1 || return 0
  if command -v timeout >/dev/null 2>&1; then
    raw="$(timeout 10 "$bin" --version 2>/dev/null </dev/null | head -n 1)"
  else
    raw="$("$bin" --version 2>/dev/null </dev/null | head -n 1)"
  fi
  ip_version_in "$raw"
}

# One line: was the loading-mechanics record measured on this CLI, or on an
# older one? The header says why the comparison runs here.
mechanics_line() {
  local measured cli
  measured="$(ip_mechanics_measured_max "$MECHANICS_RECORD")"
  if [[ -z "$measured" ]]; then
    printf -- '- Mechanics record: unchecked (no measured-on stamp found in context/verified-mechanics.md)\n'
    return 0
  fi
  cli="$(installed_cli_version)"
  if [[ -z "$cli" ]]; then
    printf -- '- Mechanics record: unchecked (installed CLI version unreadable; newest measurement %s)\n' "$measured"
  elif ip_ver_gt "$cli" "$measured"; then
    printf -- '- Mechanics record: STALE (CLI %s is newer than the newest measurement, %s; the measured cells in context/verified-mechanics.md are unverified on this CLI until its "Re-verification" repro runs again)\n' "$cli" "$measured"
  else
    printf -- '- Mechanics record: not stale (CLI %s; newest measurement %s)\n' "$cli" "$measured"
  fi
}

case "${1:-}" in
audit)
  printf -- '- Branch: %s\n' "$(branch)"
  printf -- '- Root CLAUDE.md lines: %s\n' "$(lines_of CLAUDE.md)"
  printf -- '- Root AGENTS.md lines: %s\n' "$(lines_of AGENTS.md)"
  printf -- '- Rules files: %s\n' "$(count_or_zero ip_discover_rules .)"
  printf -- '- Nested instruction files: %s\n' \
    "$(count_or_zero ip_discover_nested_instructions .)"
  mechanics_line
  ;;
check)
  printf -- '- Rules files: %s\n' "$(count_or_zero ip_discover_rules .)"
  printf -- '- Root AGENTS.md: %s\n' "$(present_or_absent AGENTS.md)"
  printf -- '- Root CLAUDE.md: %s\n' "$(present_or_absent CLAUDE.md)"
  ;;
realign)
  printf -- '- Branch: %s\n' "$(branch)"
  printf -- '- Uncommitted files: %s\n' "$(count_or_zero git status --porcelain)"
  mechanics_line
  ;;
*)
  printf 'usage: precompute.sh audit|check|realign\n' >&2
  exit 2
  ;;
esac

exit 0
