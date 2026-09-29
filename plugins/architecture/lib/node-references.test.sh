#!/usr/bin/env bash
# Self-contained tests for node-references.sh, the Node manifest reader
# map-dependencies uses (assertion primitives are duplicated on purpose, per
# docs/conventions/shell-test-helpers/README.md).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/node-references.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3
  actual: $2" ;;
  *) pass "$1" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

# shellcheck source=node-references.sh
source "$LIB"

ran="$(bash "$LIB" 2>&1)"
assert_equals "the shared reader is not a command" "$?" "2"
assert_contains "the shared reader says it is sourced" "$ran" "sourced"

T=$'\t'
pkg="$TEST_TMPDIR/package.json"
cat >"$pkg" <<'JSON'
{
  "name": "@acme/app",
  "pnpm": { "overrides": { "dependencies": { "ghost": "1.0.0" } } },
  "workspaces": { "packages": ["packages/*", "!packages/legacy"], "nohoist": ["**/native"] },
  "dependencies": { "@acme/lib": "workspace:*", "left-pad": "^1.0.0", "cat": "catalog:", "blank": "" },
  "devDependencies": {
    "vitest": "^2.0.0",
    "esc": "file:../a \"b\"",
    "nested": { "version": "1.0.0" }
  },
  "peerDependencies": { "react": ">=18" },
  "optionalDependencies": { "fsevents": "^2.0.0" },
  "scripts": { "dependencies": "not a section", "test": "vitest" }
}
JSON
records="$(node_manifest_records "$pkg")"
assert_contains "the name member is read" "$records" "name${T}@acme/app"
assert_contains "an array-in-object workspaces glob is read" "$records" "workspace${T}packages/*${T}\"packages/*\""
assert_contains "a dependency record carries section, name, spec and declaration" "$records" "dep${T}dependencies${T}left-pad${T}^1.0.0${T}\"left-pad\": \"^1.0.0\""
assert_contains "devDependencies are read" "$records" "dep${T}devDependencies${T}vitest${T}^2.0.0${T}"
assert_contains "peerDependencies are read" "$records" "dep${T}peerDependencies${T}react${T}>=18${T}"
assert_contains "optionalDependencies are read" "$records" "dep${T}optionalDependencies${T}fsevents${T}"
assert_contains "a workspace: spec is kept whole" "$records" "${T}@acme/lib${T}workspace:*${T}\"@acme/lib\": \"workspace:*\""
assert_contains "an empty spec is still a record" "$records" "dep${T}dependencies${T}blank${T}${T}\"blank\": \"\""
assert_contains "an escaped quote stays in the declaration as written" "$records" '"esc": "file:../a \"b\""'
assert_not_contains "a nested override block is not a section" "$records" "ghost"
assert_not_contains "a scripts member named dependencies is not a section" "$records" "not a section"
assert_contains "a negated glob is still emitted for the caller to refuse" "$records" "workspace${T}!packages/legacy${T}"
assert_contains "a non-string dependency value is unread" "$records" "unread${T}\"nested\": {...}"
assert_not_contains "nohoist is not a glob" "$records" "native"

array_form="$TEST_TMPDIR/array-form.json"
printf '{"workspaces":["apps/*","libs/a"],"dependencies":{"x":"1"}}\n' >"$array_form"
array_records="$(node_manifest_records "$array_form")"
assert_contains "the array form of workspaces is read" "$array_records" "workspace${T}apps/*${T}"
assert_contains "the array form keeps every glob" "$array_records" "workspace${T}libs/a${T}"

bad="$TEST_TMPDIR/bad.json"
printf '{"name":"x","dependencies":{"a":"1"' >"$bad"
assert_contains "an unterminated file is unread, not empty" "$(node_manifest_records "$bad")" "unread${T}"
assert_equals "a missing file has no records" "$(node_manifest_records "$TEST_TMPDIR/absent.json")" ""

crlf="$TEST_TMPDIR/crlf.json"
printf '{\r\n  "dependencies": {\r\n    "a": "1"\r\n  }\r\n}\r\n' >"$crlf"
assert_contains "CRLF line endings read the same" "$(node_manifest_records "$crlf")" "dep${T}dependencies${T}a${T}1${T}"

bad_workspaces="$TEST_TMPDIR/bad-workspaces.json"
printf '{"workspaces":"packages/*","dependencies":[1]}\n' >"$bad_workspaces"
bad_records="$(node_manifest_records "$bad_workspaces")"
assert_contains "a string workspaces member is unread" "$bad_records" "unread${T}\"workspaces\": \"packages/*\""
assert_contains "an array dependencies member is unread" "$bad_records" "unread${T}\"dependencies\": [...]"

yaml="$TEST_TMPDIR/pnpm-workspace.yaml"
cat >"$yaml" <<'YAML'
packages:
  - 'apps/*'
  - "libs/**"
  - tools/cli # the CLI
  - '!**/test/**'
catalog:
  react: ^18.0.0
YAML
yaml_records="$(node_pnpm_workspace_records "$yaml")"
assert_contains "a single-quoted glob is read" "$yaml_records" "workspace${T}apps/*${T}- 'apps/*'"
assert_contains "a double-quoted glob is read" "$yaml_records" "workspace${T}libs/**${T}"
assert_contains "a bare glob loses its trailing comment" "$yaml_records" "workspace${T}tools/cli${T}- tools/cli"
assert_contains "a negated glob is emitted for the caller to refuse" "$yaml_records" "workspace${T}!**/test/**${T}"
assert_not_contains "a catalog entry is not a glob" "$yaml_records" "react"

flow="$TEST_TMPDIR/flow.yaml"
printf 'packages: [apps/*, libs/*]\n' >"$flow"
assert_equals "a flow list is unread" "$(node_pnpm_workspace_records "$flow")" "unread${T}packages: [apps/*, libs/*]"

flush="$TEST_TMPDIR/flush.yaml"
printf 'packages:\n- apps/*\nother: x\n- not/a/glob\n' >"$flush"
assert_equals "an unindented list is read and stops at the next key" "$(node_pnpm_workspace_records "$flush")" "workspace${T}apps/*${T}- apps/*"

matches() {
  local re
  re="$(node_glob_regex "$1")" || {
    echo refused
    return 0
  }
  [[ "$2" =~ $re ]] && echo yes || echo no
}
assert_equals "packages/* matches a direct child" "$(matches 'packages/*' packages/a)" "yes"
assert_equals "packages/* does not match a grandchild" "$(matches 'packages/*' packages/a/b)" "no"
assert_equals "packages/** matches a grandchild" "$(matches 'packages/**' packages/a/b)" "yes"
assert_equals "a/**/c matches a/c" "$(matches 'a/**/c' a/c)" "yes"
assert_equals "a/**/c matches a/b/c" "$(matches 'a/**/c' a/b/c)" "yes"
assert_equals "a leading ./ and a trailing / are ignored" "$(matches './apps/x/' apps/x)" "yes"
assert_equals "a dot in a glob is literal" "$(matches 'a.b' aXb)" "no"
assert_equals "? is one character" "$(matches 'app?' app1)" "yes"
assert_equals "a negated glob is refused" "$(matches '!packages/x' packages/x)" "refused"
assert_equals "a brace glob is refused" "$(matches 'packages/{a,b}' packages/a)" "refused"
assert_equals "an absolute glob is refused" "$(matches '/packages/*' packages/a)" "refused"

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
