#!/usr/bin/env bash
set -uo pipefail
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/../scripts/check-good-css-drift.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed"
  exit 0
fi

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "absent: $3" "$2" ;;
    *) pass "$1" ;;
  esac
}

# shellcheck source=../scripts/check-good-css-drift.sh
source "$SCRIPT"

SHA_CHECK_CSS=6fa72714ba18cf02f698fa8015f63df043b3af85
SHA_LICENSE=66a325d82e56f2f41ebd14812517d6c50f5b66da

REAL_PLUGIN_DIR="$PLUGIN_DIR"
PLUGIN_DIR="$TMP/plugin"
mkdir -p "$PLUGIN_DIR/skills/write-css/vendor"
cp "$REAL_PLUGIN_DIR/skills/write-css/vendor/check-css.mjs" "$REAL_PLUGIN_DIR/skills/write-css/vendor/LICENSE" \
  "$PLUGIN_DIR/skills/write-css/vendor/"

out=$(run_check 2>&1)
code=$?
assert_eq "same SHAs: exit 0" 0 "$code"
assert_contains "same SHAs: reports no drift" "$out" "No drift"
assert_contains "same SHAs: names check-css.mjs" "$out" "unchanged  skills/write-css/vendor/check-css.mjs"
assert_eq "shipped copy of check-css.mjs hashes to its pin" "$SHA_CHECK_CSS" "$(git hash-object "$PLUGIN_DIR/skills/write-css/vendor/check-css.mjs")"
assert_eq "shipped copy of LICENSE hashes to its pin" "$SHA_LICENSE" "$(git hash-object "$PLUGIN_DIR/skills/write-css/vendor/LICENSE")"

mkdir -p "$TMP/bin"
for tool in bash dirname git; do ln -s "$(command -v "$tool")" "$TMP/bin/$tool"; done
out=$(env PATH="$TMP/bin" bash "$SCRIPT" --check 2>&1)
code=$?
assert_eq "no curl on PATH: exit 0" 0 "$code"
assert_not_contains "no curl on PATH: no upstream read" "$out" "Upstream"

printf '\n// local edit\n' >>"$PLUGIN_DIR/skills/write-css/vendor/check-css.mjs"
out=$(run_check 2>&1)
code=$?
assert_eq "modified vendored file: exit 1" 1 "$code"
assert_contains "modified vendored file: names the copy" "$out" "MODIFIED   skills/write-css/vendor/check-css.mjs"

rm "$PLUGIN_DIR/skills/write-css/vendor/LICENSE"
out=$(run_check 2>&1)
code=$?
assert_eq "missing vendored file: exit 1" 1 "$code"
assert_contains "missing vendored file: names the copy" "$out" "MISSING    skills/write-css/vendor/LICENSE"

bash "$SCRIPT" --help >/dev/null 2>&1
assert_eq "--help: exit 0" 0 "$?"
bash "$SCRIPT" --bogus >/dev/null 2>&1
assert_eq "unknown mode: exit 2" 2 "$?"

if ((FAILED)); then
  printf '\n%d check(s) failed.\n' "$FAILED" >&2
  exit 1
fi
printf '\nAll checks passed.\n'
