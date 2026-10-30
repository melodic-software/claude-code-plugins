#!/usr/bin/env bash
# Pins which hooks.json rows set "onFailure" (#9982). The hook-budget contract,
# "Which rows set onFailure: block", names exactly the rows that set the key;
# every other row, the advisory and SessionStart rows included, leaves it unset.
# One row per line: plugin, event, matcher, `if`, value. A row gaining or losing
# the key, or a changed value, fails here.
# test-scope: plugins/guardrails/hooks/hooks.json plugins/disk-hygiene/hooks/hooks.json
# test-scope: plugins/discovery/hooks/hooks.json plugins/multi-agent/hooks/hooks.json
# test-scope: docs/contracts/hook-budget/README.md
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
# The sibling plugins are present in the marketplace checkout and absent when
# guardrails is installed alone, so their rows skip visibly there.
MARKETPLACE="$PLUGIN_ROOT/../../.claude-plugin/marketplace.json"
# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for these tests" >&2
  exit 1
fi

TAB=$'\t'
EXPECTED="discovery${TAB}PreToolUse${TAB}Bash${TAB}${TAB}block
disk-hygiene${TAB}PreToolUse${TAB}Bash${TAB}Bash(*hygiene.py*)${TAB}block
disk-hygiene${TAB}PreToolUse${TAB}PowerShell${TAB}PowerShell(*hygiene.py*)${TAB}block
guardrails${TAB}PreToolUse${TAB}Write|Edit|NotebookEdit${TAB}${TAB}block
guardrails${TAB}PreToolUse${TAB}^mcp__(plugin_.+_)?github__(push_files|create_or_update_file)\$${TAB}${TAB}block
guardrails${TAB}PreToolUse${TAB}^mcp__.+__(merge_pull_request|enable_pr_auto_merge)\$${TAB}${TAB}block
guardrails${TAB}PreToolUse${TAB}^mcp__(plugin_.+_)?github__(add_issue_comment|update_issue_comment|issue_write|create_issue|update_issue|create_pull_request|update_pull_request|add_comment_to_pending_review|add_reply_to_pull_request_comment|pull_request_review_write|create_pull_request_review|create_and_submit_pull_request_review|submit_pending_pull_request_review|discussion_comment_write)\$${TAB}${TAB}block
guardrails${TAB}PreToolUse${TAB}Bash|PowerShell${TAB}${TAB}block
multi-agent${TAB}PreToolUse${TAB}WebFetch${TAB}${TAB}block
multi-agent${TAB}PreToolUse${TAB}Bash${TAB}${TAB}block"

# rows <plugin> <hooks.json>: every hook in the file that sets onFailure.
rows() {
  jq -r --arg p "$1" '
    (.hooks // {}) | to_entries[] | .key as $e | .value[]? | (.matcher // "") as $m
    | .hooks[]? | select(type == "object" and has("onFailure"))
    | [$p, $e, $m, (.if // ""), (.onFailure | tostring)] | join("\t")' "$2"
}

if [[ -f "$MARKETPLACE" ]]; then
  files=("$PLUGIN_ROOT"/../*/hooks/hooks.json)
else
  echo "SKIP: sibling plugins' rows not checked, no marketplace checkout at $MARKETPLACE"
  files=("$HOOK_DIR/hooks.json")
  EXPECTED=$(grep "^guardrails$TAB" <<<"$EXPECTED")
fi

actual=""
for f in "${files[@]}"; do
  plugin="${f%/hooks/hooks.json}"
  plugin="${plugin##*/}"
  if ! out=$(rows "$plugin" "$f"); then
    bad "$plugin: hooks.json does not parse"
    continue
  fi
  [[ -n "$out" ]] && actual+="$out"$'\n'
done

expected_sorted=$(LC_ALL=C sort <<<"$EXPECTED")
actual_sorted=$(printf '%s' "$actual" | LC_ALL=C sort)
assert_eq "the onFailure rows are exactly the contract's block rows" \
  "$expected_sorted" "$actual_sorted"

# The advisory rows the contract names stay without the key. The exact-set
# check covers them too; these name the row when one gains it.
assert_eq "guardrails Workflow row leaves onFailure unset" "false" \
  "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Workflow") | .hooks[] | has("onFailure")] | any' "$HOOK_DIR/hooks.json")"
assert_eq "no guardrails SessionStart row sets onFailure" "false" \
  "$(jq -r '[.hooks.SessionStart[]?.hooks[] | has("onFailure")] | any' "$HOOK_DIR/hooks.json")"

report
