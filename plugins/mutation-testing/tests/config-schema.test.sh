#!/usr/bin/env bash
# test-scope: plugins/mutation-testing/schemas/mutation-testing.schema.json
# test-scope: plugins/mutation-testing/skills/audit/context/config-fallback.md
# test-scope: plugins/mutation-testing/skills/setup/templates/config-template.md
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$PLUGIN_DIR/schemas/mutation-testing.schema.json"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT

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

validates() {
  node -e '
const schema = require(process.argv[1]);
const config = JSON.parse(process.argv[2]);
const fits = (s, v) => {
  if (s.type === "string" && typeof v !== "string") return false;
  if (s.type === "integer" && !Number.isInteger(v)) return false;
  if (s.type === "array" && !Array.isArray(v)) return false;
  if (Array.isArray(s.enum) && !s.enum.includes(v)) return false;
  if (typeof v === "string" && v.length < (s.minLength ?? 0)) return false;
  return true;
};
for (const [k, v] of Object.entries(config)) {
  const s = schema.properties[k];
  if (s === undefined ? schema.additionalProperties === false : !fits(s, v)) process.exit(3);
}' "$SCHEMA" "$1"
}

expect() {
  local label="$1" expected="$2" config="$3" code
  validates "$config"
  code=$?
  if [[ "$code" -eq "$expected" ]]; then ok "$label"; else fail "$label (exit $code)"; fi
}

expect 'tool: cargo-mutants validates' 0 '{"tool":"cargo-mutants"}'
expect 'tool: manual validates' 0 '{"tool":"manual"}'
expect 'tool: stryker-js validates' 0 '{"tool":"stryker-js"}'
expect 'an empty tool is refused' 3 '{"tool":""}'
expect 'a non-string tool is refused' 3 '{"tool":3}'
expect 'an unknown key is still refused' 3 '{"tool":"manual","tools":"mutmut"}'

if node -e 'const t = require(process.argv[1]).properties.tool; process.exit(t.enum === undefined && t.type === "string" ? 0 : 1)' "$SCHEMA"; then
  ok 'tool is a string with no closed list'
else
  fail 'tool is a string with no closed list'
fi

if grep -qF 'no shipped adapter' "$PLUGIN_DIR/skills/audit/context/config-fallback.md"; then
  ok 'the audit names a tool with no shipped adapter'
else
  fail 'the audit names a tool with no shipped adapter'
fi

if command -v check-jsonschema >/dev/null 2>&1; then
  check_yaml() {
    local label="$1" expected="$2" text="$3" file code
    file="$(mktemp -d "$WORKROOT/case.XXXXXX")/mutation-testing.yaml"
    printf '%s\n' "$text" >"$file"
    check-jsonschema --schemafile "$SCHEMA" -- "$file" >/dev/null 2>&1
    code=$?
    if [[ "$code" -eq "$expected" ]]; then ok "check-jsonschema: $label"; else fail "check-jsonschema: $label (exit $code)"; fi
  }
  check_yaml 'tool: cargo-mutants validates' 0 'tool: cargo-mutants'
  check_yaml 'tool: manual validates' 0 'tool: manual'
  check_yaml 'an empty tool is refused' 1 'tool: ""'
else
  echo "SKIP: check-jsonschema not installed; the node pass above stands alone" >&2
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
