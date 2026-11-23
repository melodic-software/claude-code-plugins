#!/usr/bin/env bash
# The ecosystem-commands examples validate against ecosystem.schema.json, and an
# example missing the required `globs` key does not. Well-formed `requires`
# declarations validate; malformed ones do not.
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

# requires: a well-formed declaration validates; an entry with no probe, or a
# key that names no command, does not.
write_requires() {
  printf 'globs: ["*.yml"]\ncheck-cmd: "node tools/policy.mjs"\nrequires:\n  %s:\n    - name: ajv\n%b' "$1" "$2" >"$tmp/$3.yaml"
}
write_requires check-cmd '      probe: "test -d tools/node_modules/ajv"\n      hint: "npm ci in tools/"\n' requires-ok
write_requires check-cmd '      hint: "npm ci in tools/"\n' requires-no-probe
write_requires lint-cmd '      probe: "test -d tools/node_modules/ajv"\n' requires-bad-key
write_requires check-cmd '      probe: "test -d tools/node_modules/ajv"\n      run-from: elsewhere\n' requires-bad-run-from
printf 'globs: ["*.yml"]\ngates:\n  - name: policy\n    cmd: "node tools/policy.mjs"\n    requires:\n      - name: ajv\n        probe: "test -d tools/node_modules/ajv"\n        run-from: ecosystem\n' >"$tmp/requires-gate-ok.yaml"
probe='      probe: "test -d tools/node_modules/ajv"\n'
write_requires check-cmd "$probe"'      install:\n        manager: npm\n        lockfile: tools/package-lock.json\n' install-ok
write_requires check-cmd "$probe"'      install:\n        manager: npm\n        lockfile: tools/package-lock.json\n        command: "npm install"\n' install-extra-key
write_requires check-cmd "$probe"'      install:\n        manager: uv\n        lockfile: uv.lock\n' install-bad-manager
write_requires check-cmd "$probe"'      install:\n        manager: npm\n' install-no-lockfile
write_requires check-cmd "$probe"'      install:\n        manager: npm\n        lockfile: ../package-lock.json\n' install-escapes
write_requires check-cmd "$probe"'      install:\n        manager: npm\n        lockfile: /package-lock.json\n' install-absolute
for good_case in requires-ok requires-gate-ok install-ok; do
  if out="$("$validator" --schemafile "$SCHEMA" "$tmp/$good_case.yaml" 2>&1)"; then
    ok "$good_case validates"
  else
    bad "$good_case does not validate: $out"
  fi
done
for bad_case in requires-no-probe requires-bad-key requires-bad-run-from install-extra-key install-bad-manager \
  install-no-lockfile install-escapes install-absolute; do
  if "$validator" --schemafile "$SCHEMA" "$tmp/$bad_case.yaml" >/dev/null 2>&1; then
    bad "$bad_case validates"
  else
    ok "$bad_case is rejected"
  fi
done

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
((fail == 0))
