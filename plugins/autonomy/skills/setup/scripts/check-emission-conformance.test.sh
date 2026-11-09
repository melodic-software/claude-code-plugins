#!/usr/bin/env bash
# Tests for check-emission-conformance.mjs: exit codes, the OK line's counts
# and the FAILED findings, over throwaway OTLP JSON-lines fixtures built here.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SELF_DIR/check-emission-conformance.mjs"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

PIN="https://opentelemetry.io/schemas/1.43.0"
JOIN='{"key":"autonomy.work_item.url","value":{"stringValue":"https://tracker.example/o/r/items/1"}}'

# expect <name> <exit-code> <substring> <target>...: runs the checker on the
# targets and asserts its exit code and that its combined output holds the
# substring verbatim.
expect() {
  local name="$1" want_code="$2" want_text="$3"
  shift 3
  local out code
  out="$(node "$CHECK" "$@" 2>&1)"
  code=$?
  if [[ $code -ne $want_code ]]; then
    fail "$name: exit $code, want $want_code; output: $out"
  elif [[ "$out" != *"$want_text"* ]]; then
    fail "$name: output lacks \"$want_text\"; output: $out"
  else
    ok "$name"
  fi
}

# --- conformant: resource-level schemaUrl ------------------------------------
printf '%s\n' "{\"resourceSpans\":[{\"schemaUrl\":\"$PIN\",\"resource\":{\"attributes\":[$JOIN]},\"scopeSpans\":[]}]}" \
  >"$tmp/resource-schema.jsonl"
expect "resource_schema_url" 0 \
  "Emission conformance OK: 1 OTLP JSON lines, 1 join-attribute occurrence(s), 1 pinned schemaUrl declaration(s)." \
  "$tmp/resource-schema.jsonl"

# --- conformant: scope-level schemaUrl only is counted -----------------------
printf '%s\n' "{\"resourceSpans\":[{\"resource\":{\"attributes\":[]},\"scopeSpans\":[{\"schemaUrl\":\"$PIN\",\"scope\":{\"name\":\"s\"},\"spans\":[{\"name\":\"x\",\"attributes\":[$JOIN]}]}]}]}" \
  >"$tmp/scope-schema.jsonl"
expect "scope_schema_url_counted" 0 \
  "Emission conformance OK: 1 OTLP JSON lines, 1 join-attribute occurrence(s), 1 pinned schemaUrl declaration(s)." \
  "$tmp/scope-schema.jsonl"

# --- conformant: resource and scope declarations both count (logs signal) ----
printf '%s\n' "{\"resourceLogs\":[{\"schemaUrl\":\"$PIN\",\"resource\":{\"attributes\":[$JOIN]},\"scopeLogs\":[{\"schemaUrl\":\"$PIN\",\"logRecords\":[{\"attributes\":[$JOIN]}]}]}]}" \
  >"$tmp/both-levels.jsonl"
expect "resource_and_scope_counted" 0 \
  "Emission conformance OK: 1 OTLP JSON lines, 2 join-attribute occurrence(s), 2 pinned schemaUrl declaration(s)." \
  "$tmp/both-levels.jsonl"

# --- conformant: one declaration anywhere in the set suffices; non-JSON files
# in a directory are skipped ---------------------------------------------------
mkdir -p "$tmp/set"
printf '%s\n' "{\"resourceSpans\":[{\"resource\":{\"attributes\":[$JOIN]},\"scopeSpans\":[]}]}" >"$tmp/set/a.jsonl"
printf '%s\n' "{\"resourceMetrics\":[{\"schemaUrl\":\"$PIN\",\"resource\":{\"attributes\":[$JOIN]},\"scopeMetrics\":[]}]}" >"$tmp/set/b.ndjson"
printf '%s\n' "not json at all" >"$tmp/set/notes.txt"
expect "set_wide_declaration" 0 \
  "Emission conformance OK: 2 OTLP JSON lines, 2 join-attribute occurrence(s), 1 pinned schemaUrl declaration(s)." \
  "$tmp/set"

# --- finding: no emission declares the pinned schemaUrl ----------------------
printf '%s\n' "{\"resourceSpans\":[{\"resource\":{\"attributes\":[$JOIN]},\"scopeSpans\":[]}]}" \
  >"$tmp/no-schema.jsonl"
expect "no_schema_url" 1 \
  "no emission in the set declares the pinned schemaUrl ($PIN)" \
  "$tmp/no-schema.jsonl"

# --- finding: a scope-level schemaUrl off the pin ----------------------------
printf '%s\n' "{\"resourceSpans\":[{\"schemaUrl\":\"$PIN\",\"resource\":{\"attributes\":[$JOIN]},\"scopeSpans\":[{\"schemaUrl\":\"https://opentelemetry.io/schemas/1.20.0\",\"spans\":[]}]}]}" \
  >"$tmp/wrong-scope.jsonl"
expect "scope_schema_url_off_pin" 1 \
  "$tmp/wrong-scope.jsonl:1 resourceSpans[0] scope: schemaUrl https://opentelemetry.io/schemas/1.20.0 != pinned $PIN" \
  "$tmp/wrong-scope.jsonl"

# --- finding: an unjoined entry beside a joined one on the same line ---------
printf '%s\n' "{\"resourceSpans\":[{\"schemaUrl\":\"$PIN\",\"resource\":{\"attributes\":[$JOIN]},\"scopeSpans\":[]},{\"resource\":{\"attributes\":[]},\"scopeSpans\":[]}]}" \
  >"$tmp/unjoined.jsonl"
expect "unjoined_entry" 1 \
  "$tmp/unjoined.jsonl:1 resourceSpans[1]: resource entry carries no autonomy.work_item.url attribute" \
  "$tmp/unjoined.jsonl"

# --- finding: a join value that is not a normalized canonical URL ------------
printf '%s\n' "{\"resourceSpans\":[{\"schemaUrl\":\"$PIN\",\"resource\":{\"attributes\":[{\"key\":\"autonomy.work_item.url\",\"value\":{\"stringValue\":\"https://tracker.example/o/r/items/1/\"}}]},\"scopeSpans\":[]}]}" \
  >"$tmp/trailing-slash.jsonl"
expect "join_value_not_normalized" 1 \
  "is not a normalized canonical item URL" \
  "$tmp/trailing-slash.jsonl"

# --- findings: invalid JSON, and a line with no resource entries --------------
printf '%s\n' "{not json" >"$tmp/invalid.jsonl"
expect "invalid_json_line" 1 "$tmp/invalid.jsonl:1: not valid JSON" "$tmp/invalid.jsonl"
printf '%s\n' '{"foo":1}' >"$tmp/no-entries.jsonl"
expect "no_resource_entries" 1 \
  "$tmp/no-entries.jsonl:1: no OTLP resource entries found on this line" \
  "$tmp/no-entries.jsonl"

# --- finding: nothing to check ----------------------------------------------
mkdir -p "$tmp/empty"
expect "empty_target" 1 "no OTLP JSON lines found under the given targets" "$tmp/empty"

# --- usage error -------------------------------------------------------------
expect "no_arguments" 2 "usage: check-emission-conformance.mjs"

echo
echo "Passed: $PASS  Failed: $FAIL"
if [[ $FAIL -ne 0 ]]; then
  exit 1
fi
exit 0
