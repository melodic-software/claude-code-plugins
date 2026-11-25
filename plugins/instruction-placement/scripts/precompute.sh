#!/usr/bin/env bash
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
  git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\r'
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
