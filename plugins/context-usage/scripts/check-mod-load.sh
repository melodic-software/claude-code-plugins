#!/usr/bin/env bash
# check-mod-load.sh
# Read-only. Prints TSV rows `check<TAB>PASS|FAIL|INFO<TAB>detail`: Claude Code
# against the mods floor in prerequisites.json, then how to read this session's
# state. Exits 1 when a row fails. Installs nothing. Takes no arguments.
#
# The session row is INFO because only the agent sees its own tool list; a child
# process never sees this session's flags or settings overlay.
# What turns mods off, and the floor's source:
# https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off
# Reading `claude plugin test`:
# https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load
set -uo pipefail

if [[ $# -gt 0 ]]; then
  echo "check-mod-load: takes no arguments" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
floor="$(sed -n '/"id": "claude"/,/"min"/s/.*"min": *"\([0-9.]*\)".*/\1/p' "$ROOT/prerequisites.json")"
failed=0
row() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
  [[ "$2" == FAIL ]] && failed=1
}

version="$(claude --version 2>/dev/null)"
version="${version%% *}"
if [[ -z "$floor" ]]; then
  row mods-floor FAIL "prerequisites.json declares no mods floor on its claude entry"
elif [[ -z "$version" ]]; then
  row mods-floor FAIL "claude did not report a version, so the mods floor $floor could not be checked"
elif awk -v v="$version" -v f="$floor" 'BEGIN {
  nv = split(v, a, "."); nf = split(f, b, ".")
  for (i = 1; i <= (nv > nf ? nv : nf); i++) {
    if (a[i] + 0 != b[i] + 0) exit (a[i] + 0 < b[i] + 0)
  }
}'; then
  row mods-floor PASS "claude $version meets the mods floor $floor"
else
  row mods-floor FAIL "mods off: claude $version is older than the mods floor $floor, unsupported"
fi

row session INFO "look for mcp__context-usage__status in your own tool list, deferred names included, and do not call it. Present: the mod is running in this session. Absent: mods are off in this session, or policy refused the tool, which leaves one debug-log line; state both causes. With mods off there are no zone lines and no module writes here; the PostCompact marker hook still runs wherever settings hooks do. A claude plugin test run only says whether mods can load on this build, never this session's state."

exit "$failed"
