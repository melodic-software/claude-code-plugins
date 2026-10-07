#!/usr/bin/env bash
# check.sh
# Read-only. Prints TSV rows `check<TAB>PASS|FAIL<TAB>detail` for node, the
# WebFetch truncation hook's registration in hooks/hooks.json, and the hook's
# answer to a sample truncated WebFetch result. Exits 1 when any row fails.
# Installs nothing. Takes no arguments: the plugin root is always the one this
# script ships in, so the skill's allowed-tools grant can never point node at
# another file.
set -uo pipefail

if [[ $# -gt 0 ]]; then
  echo "check: takes no arguments" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOK="$ROOT/hooks/webfetch-truncation.mjs"
HOOKS="$ROOT/hooks/hooks.json"
failed=0
row() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
  [[ "$2" == PASS ]] || failed=1
}

node_path="$(command -v node 2>/dev/null || true)"
if [[ -n "$node_path" ]]; then
  row node PASS "$node_path $(node --version 2>&1)"
else
  row node FAIL "node is not on PATH; the truncation hook cannot start and adds nothing"
fi

# With node, one hook entry must carry the event, matcher, command and script
# together. Without node, a text match still reports, marked as unverified.
# The ${CLAUDE_PLUGIN_ROOT} token is searched for verbatim, as hooks.json spells it.
# shellcheck disable=SC2016
SCRIPT_ARG='${CLAUDE_PLUGIN_ROOT}/hooks/webfetch-truncation.mjs'
if [[ ! -f "$HOOKS" ]]; then
  row registration FAIL "$HOOKS is missing"
elif [[ ! -f "$HOOK" ]]; then
  row registration FAIL "$HOOK is missing"
elif [[ -n "$node_path" ]]; then
  if node -e '
    const [file, arg] = process.argv.slice(1)
    const groups = (JSON.parse(require("fs").readFileSync(file, "utf8")).hooks || {}).PostToolUse || []
    const ok = groups.some(g => g.matcher === "WebFetch" && (g.hooks || []).some(h =>
      h.type === "command" && h.command === "node" && Array.isArray(h.args) && h.args.includes(arg)))
    process.exit(ok ? 0 : 1)
  ' "$HOOKS" "$SCRIPT_ARG" 2>/dev/null; then
    row registration PASS "PostToolUse WebFetch -> node webfetch-truncation.mjs"
  else
    row registration FAIL "no PostToolUse WebFetch hook entry runs node on webfetch-truncation.mjs"
  fi
elif grep -q '"PostToolUse"' "$HOOKS" && grep -q '"matcher": *"WebFetch"' "$HOOKS" &&
  grep -q '"command": *"node"' "$HOOKS" && grep -qF "$SCRIPT_ARG" "$HOOKS"; then
  row registration PASS "text match only; one-entry structure is checked when node resolves"
else
  row registration FAIL "hooks.json does not name the PostToolUse WebFetch truncation hook"
fi

if [[ -z "$node_path" ]]; then
  row hook FAIL "not run: node is missing"
elif [[ ! -f "$HOOK" ]]; then
  row hook FAIL "not run: $HOOK is missing"
else
  out="$(printf '%s' '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com/page.md"},"tool_response":{"result":"# Page\n\n[Content truncated for length...]"}}' |
    node "$HOOK" 2>&1)"
  if grep -q '"additionalContext"' <<<"$out"; then
    row hook PASS "flags a sample truncated WebFetch result"
  else
    row hook FAIL "did not flag a sample truncated WebFetch result: ${out:-<no output>}"
  fi
fi

exit "$failed"
