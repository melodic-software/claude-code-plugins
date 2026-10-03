#!/usr/bin/env bash
# check.sh [--plugin-root <dir>]
# Read-only. Prints TSV rows `check<TAB>PASS|FAIL<TAB>detail` for node, the
# fetch gate's registration in hooks/hooks.json, and the gate's answer to an
# off-host drift-checker fetch. Exits 1 when any row fails. Installs nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --plugin-root)
    [[ $# -gt 1 ]] || {
      echo "check: --plugin-root needs a directory" >&2
      exit 2
    }
    ROOT="$2"
    shift
    ;;
  *)
    echo "check: unknown argument '$1'" >&2
    exit 2
    ;;
  esac
  shift
done

GATE="$ROOT/hooks/drift-checker-fetch-gate.mjs"
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
  row node FAIL "node is not on PATH; the fetch gate cannot start and fails open"
fi

# Registration is read without node so it still reports when node is missing.
# The ${CLAUDE_PLUGIN_ROOT} token is searched for verbatim, as hooks.json spells it.
# shellcheck disable=SC2016
if [[ ! -f "$HOOKS" ]]; then
  row registration FAIL "$HOOKS is missing"
elif ! grep -q '"PreToolUse"' "$HOOKS" || ! grep -q '"matcher": *"WebFetch"' "$HOOKS" ||
  ! grep -q '"command": *"node"' "$HOOKS" ||
  ! grep -qF '${CLAUDE_PLUGIN_ROOT}/hooks/drift-checker-fetch-gate.mjs' "$HOOKS"; then
  row registration FAIL "hooks.json has no PreToolUse WebFetch entry running node on drift-checker-fetch-gate.mjs"
elif [[ ! -f "$GATE" ]]; then
  row registration FAIL "$GATE is missing"
else
  row registration PASS "PreToolUse WebFetch -> node drift-checker-fetch-gate.mjs"
fi

if [[ -z "$node_path" ]]; then
  row gate FAIL "not run: node is missing"
elif [[ ! -f "$GATE" ]]; then
  row gate FAIL "not run: $GATE is missing"
else
  out="$(printf '%s' '{"agent_type":"multi-agent:drift-checker","tool_name":"WebFetch","tool_input":{"url":"https://example.com/"}}' |
    node "$GATE" 2>&1)"
  if grep -q '"permissionDecision":"deny"' <<<"$out"; then
    row gate PASS "denies an off-host drift-checker fetch"
  else
    row gate FAIL "did not deny an off-host drift-checker fetch: ${out:-<no output>}"
  fi
fi

exit "$failed"
