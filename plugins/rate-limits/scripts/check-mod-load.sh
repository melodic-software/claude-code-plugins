#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/mod-load-check.sh
. "$ROOT/lib/mod-load-check.sh" || exit 2
mod_load_check "$ROOT" "look for mcp__rate-limits__status in your own tool list, deferred names included, and do not call it. Present: the mod is running in this session. Absent: mods are off in this session, or policy refused the tool, which the module logs as one debug-log line; state both causes without picking one. The StopFailure hook still records rate-limit stops either way. A claude plugin test run only says whether mods can load on this build, never this session's state." "$@"
