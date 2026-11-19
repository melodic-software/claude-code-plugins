# shellcheck shell=bash

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
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else fail "$1 (missing: $3; got: ${2:0:400})"; fi
}
assert_not_contains() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else fail "$1 (unexpected: $3)"; fi
}
assert_empty() {
  if [[ -z "$2" ]]; then ok "$1"; else fail "$1 (got: ${2:0:400})"; fi
}
