#!/usr/bin/env bash
# The ecosystem-commands examples validate against ecosystem.schema.json, and an
# example missing the required `globs` key does not.
#
#   bash docs/contracts/ecosystem-commands/examples.test.sh
#
# Validator: check-jsonschema (CHECK_JSONSCHEMA_BIN overrides), as
# scripts/check-convention-yaml.sh uses. Without it the cases are skipped, not
# passed.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="$(cd "$DIR/../../.." && pwd)" || exit 2
# The contract moved from docs/conventions/, which keeps stubs; a file is read
# from the old home only when the new one lacks it.
home_of() {
  if [[ -f "$ROOT/$1" ]]; then printf '%s' "$1"; else printf '%s' "docs/conventions/${1#docs/contracts/}"; fi
}
SCHEMA="$ROOT/$(home_of docs/contracts/ecosystem-commands/ecosystem.schema.json)"
EXAMPLES=(
  docs/contracts/ecosystem-commands/examples/bash.yaml
  docs/contracts/ecosystem-commands/examples/dotnet.yaml
  docs/contracts/ecosystem-commands/examples/go.yaml
  docs/contracts/ecosystem-commands/examples/python.yaml
)
validator="${CHECK_JSONSCHEMA_BIN:-check-jsonschema}"
if ! command -v "$validator" >/dev/null 2>&1; then
  printf 'skip: %s not on PATH; the ecosystem example cases did not run\n' "$validator"
  exit 0
fi

pass=0 fail=0
ok() {
  pass=$((pass + 1))
  printf 'ok: %s\n' "$1"
}
bad() {
  fail=$((fail + 1))
  printf 'FAIL: %s\n' "$1"
}

for f in "${EXAMPLES[@]}"; do
  f="$(home_of "$f")"
  if out="$("$validator" --schemafile "$SCHEMA" "$ROOT/$f" 2>&1)"; then
    ok "$f validates"
  else
    bad "$f does not validate: $out"
  fi
done

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
grep -v '^globs:' "$ROOT/$(home_of "${EXAMPLES[0]}")" >"$tmp/no-globs.yaml"
if "$validator" --schemafile "$SCHEMA" "$tmp/no-globs.yaml" >/dev/null 2>&1; then
  bad "an example without globs validates"
else
  ok "an example without globs is rejected"
fi

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
((fail == 0))
