#!/usr/bin/env bash
# Self-contained tests for go-references.sh, the Go manifest reader
# map-dependencies uses (assertion primitives are duplicated on purpose, per
# docs/conventions/shell-test-helpers/README.md).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/go-references.sh"
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

# shellcheck source=go-references.sh
source "$LIB"

ran="$(bash "$LIB" 2>&1)"
assert_equals "the shared reader is not a command" "$?" "2"
assert_contains "the shared reader says it is sourced" "$ran" "sourced"

T=$'\t'
mod="$TEST_TMPDIR/go.mod"
cat >"$mod" <<EOF
// a comment line
module example.com/acme/app // trailing comment

go 1.22
toolchain go1.22.1

require github.com/pkg/errors v0.9.1
require (
${T}github.com/spf13/cobra v1.8.0 // indirect
${T}"quoted.example/mod" v1.0.0
)
replace example.com/acme/lib => ../lib
replace (
${T}example.com/acme/util v1.0.0 => ./util
${T}github.com/pkg/errors => github.com/fork/errors v0.9.2
)
exclude github.com/bad/mod v1.0.0
retract v1.0.1
tool (
${T}golang.org/x/tools/cmd/stringer
)
frobnicate something odd
require github.com/incomplete
mystery (
${T}a b
)
EOF
records="$(go_mod_records "$mod")"
assert_contains "the module directive is read past a trailing comment" "$records" "module${T}example.com/acme/app"
assert_contains "a single-line require is read with its declaration" "$records" "require${T}github.com/pkg/errors${T}v0.9.1${T}require github.com/pkg/errors v0.9.1"
assert_contains "a block require is read and its comment removed" "$records" "require${T}github.com/spf13/cobra${T}v1.8.0${T}github.com/spf13/cobra v1.8.0"
assert_contains "a quoted module path is unquoted" "$records" "require${T}quoted.example/mod${T}v1.0.0${T}"
assert_contains "a single-line local replace is local" "$records" "replace${T}example.com/acme/lib${T}../lib${T}1${T}replace example.com/acme/lib => ../lib"
assert_contains "a block replace with an old version is local" "$records" "replace${T}example.com/acme/util${T}./util${T}1${T}example.com/acme/util v1.0.0 => ./util"
assert_contains "a module replace is not local" "$records" "replace${T}github.com/pkg/errors${T}github.com/fork/errors${T}0${T}"
assert_not_contains "go, toolchain, exclude, retract and tool give no line" "$records" "toolchain"
assert_not_contains "a tool block gives no line" "$records" "stringer"
assert_contains "an unknown directive is unread" "$records" "unread${T}frobnicate something odd"
assert_contains "a require with no version is unread" "$records" "unread${T}require github.com/incomplete"
assert_contains "an unknown block is unread once" "$records" "unread${T}mystery ("
assert_not_contains "an unknown block's members are skipped" "$records" "a b"

work="$TEST_TMPDIR/go.work"
cat >"$work" <<EOF
go 1.22
use ./app
use (
${T}./lib // shared
${T}"./quoted"
)
replace example.com/x => ./x
EOF
wrecords="$(go_work_records "$work")"
assert_contains "a go.work use line is read" "$wrecords" "use${T}./app${T}use ./app"
assert_contains "a block use line is read and its comment removed" "$wrecords" "use${T}./lib${T}./lib"
assert_contains "a quoted use path is unquoted" "$wrecords" "use${T}./quoted${T}"
assert_contains "a go.work replace is unread" "$wrecords" "unread${T}replace example.com/x => ./x"

printf 'module x\nrequire (\n\ta v1\n' >"$TEST_TMPDIR/open.mod"
assert_contains "an unterminated block is unread" "$(go_mod_records "$TEST_TMPDIR/open.mod")" "unread${T}<unterminated block: require ("
assert_equals "a missing file gives nothing" "$(go_mod_records "$TEST_TMPDIR/absent")" ""

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
