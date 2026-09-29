#!/usr/bin/env bash
# Unit tests for resolve-diagram-dialect.sh. The system key has no default and
# refuses mermaid; the data key defaults to mermaid.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$SCRIPT_DIR/resolve-diagram-dialect.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}

doc() {
  # shellcheck disable=SC2016 # the fence is literal markdown
  printf '```yaml\ndiagram_dialect:\n%s```\n' "$1" >"$TMP/formats.md"
}

doc $'  data: dbml\n  system: likec4   # a comment\n'
assert_equals "system likec4" "$(bash "$RESOLVE" --kind system --formats "$TMP/formats.md")" "likec4"
assert_equals "data dbml" "$(bash "$RESOLVE" --kind data --formats "$TMP/formats.md")" "dbml"

doc $'  system: "c4-plantuml"\n'
assert_equals "system c4-plantuml, quoted" "$(bash "$RESOLVE" --kind system --formats "$TMP/formats.md")" "c4-plantuml"
assert_equals "data absent defaults to mermaid" "$(bash "$RESOLVE" --kind data --formats "$TMP/formats.md" 2>/dev/null)" "mermaid"

doc $'  system: mermaid\n'
got="$(bash "$RESOLVE" --kind system --formats "$TMP/formats.md" 2>"$TMP/err")"
assert_equals "system mermaid is refused" "$got" "none"
assert_contains "refusal names the value" "$(cat "$TMP/err")" "unrecognized value mermaid"

doc $'  data: mermaid\n'
got="$(bash "$RESOLVE" --kind system --formats "$TMP/formats.md" 2>"$TMP/err")"
assert_equals "system absent emits nothing" "$got" "none"
assert_contains "absent says no view" "$(cat "$TMP/err")" "unset (no C4 view emitted)"

got="$(bash "$RESOLVE" --kind system --formats "$TMP/missing.md" 2>/dev/null)"
assert_equals "system without a doc emits nothing" "$got" "none"
got="$(bash "$RESOLVE" --kind system 2>/dev/null)"
assert_equals "system without --formats emits nothing" "$got" "none"

bash "$RESOLVE" --kind other >/dev/null 2>&1
assert_equals "an unknown kind is a usage error" "$?" "2"

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
