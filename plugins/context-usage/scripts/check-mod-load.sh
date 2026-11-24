#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/mod-load-check.sh
. "$ROOT/lib/mod-load-check.sh" || exit 2
mod_load_check "$ROOT" "look for mcp__context-usage__status in your own tool list, deferred names included, and do not call it. Present: the mod is running in this session. Absent: mods are off in this session, or policy refused the tool, which leaves one debug-log line; state both causes. With mods off there are no zone lines and no module writes here; the PostCompact marker hook still runs wherever settings hooks do. A claude plugin test run only says whether mods can load on this build, never this session's state." "$@"
