#!/usr/bin/env bash
# check-hook-registration.sh
# Read-only. Prints TSV rows `check<TAB>PASS|FAIL<TAB>detail` for node, the
# fetch gate's registration in hooks/hooks.json, and the gate's answer to an
# off-host drift-checker fetch. Exits 1 when any row fails. Installs nothing.
# Takes no arguments: the plugin root is always the one this script ships in.
set -uo pipefail

HR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/hook-registration-check.sh
. "$HR_ROOT/lib/hook-registration-check.sh" || exit 2
HR_HOOK=drift-checker-fetch-gate.mjs
HR_EVENT=PreToolUse
HR_MATCHER=WebFetch
HR_ROW=gate
HR_NODE_FAIL="node is not on PATH; the fetch gate cannot start, so Claude Code 2.1.295 or later denies every WebFetch and an older client lets it through"
HR_TEXT_FAIL="hooks.json does not name the PreToolUse WebFetch node gate"
HR_SAMPLE='{"agent_type":"multi-agent:drift-checker","tool_name":"WebFetch","tool_input":{"url":"https://example.com/"}}'
HR_EXPECT='"permissionDecision":"deny"'
HR_SAMPLE_PASS="denies an off-host drift-checker fetch"
HR_SAMPLE_FAIL="did not deny an off-host drift-checker fetch"
hook_registration_check "$@"
