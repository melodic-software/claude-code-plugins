#!/usr/bin/env bash
# test-scope: plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/README.md
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HOOK_DIR/../.claude-plugin/plugin.json"
README="$HOOK_DIR/../README.md"

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free

SWITCHES_THAT_ARE_NOT_GUARDS='["git_hooks_notice_enabled"]'

count=$(jq --argjson not "$SWITCHES_THAT_ARE_NOT_GUARDS" '.userConfig | keys | map(select(endswith("_enabled"))) - $not | length' "$MANIFEST")
description=$(jq -r '.description' "$MANIFEST")

assert_contains "the manifest description states the toggleable guard count" "$description" "$count toggleable guards"
assert_contains "the README intro states the toggleable guard count" "$(sed -n 3p "$README")" "$count toggleable **safety guards**"

report
