#!/usr/bin/env bash
set -uo pipefail

HR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/hook-registration-check.sh
. "$HR_ROOT/lib/hook-registration-check.sh" || exit 2
HR_HOOK=webfetch-truncation.mjs
HR_EVENT=PostToolUse
HR_MATCHER=WebFetch
HR_ROW=hook
HR_NODE_FAIL="node is not on PATH; the truncation hook cannot start and adds nothing"
HR_TEXT_FAIL="hooks.json does not name the PostToolUse WebFetch truncation hook"
HR_SAMPLE='{"tool_name":"WebFetch","tool_input":{"url":"https://example.com/page.md"},"tool_response":{"result":"# Page\n\n[Content truncated for length...]"}}'
HR_EXPECT='"additionalContext"'
HR_SAMPLE_PASS="flags a sample truncated WebFetch result"
HR_SAMPLE_FAIL="did not flag a sample truncated WebFetch result"
hook_registration_check "$@"
