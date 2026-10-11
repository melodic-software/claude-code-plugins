#!/usr/bin/env bash
# Exit-code contract of scripts/check-good-css-drift.sh, network-free: the
# script is sourced and fetch_blob_sha is replaced by a stub. The expected
# SHAs are the upstream blob SHAs at pin b645ab15 recorded in
# docs/upstream/good-css.md, not values read from the script.
set -uo pipefail

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
SHA_PRACTICES=7d746e65d56ee4910572b75738051482f4735f38
CHANGED_SHA=0123456789abcdef0123456789abcdef01234567

stub_practices="$SHA_PRACTICES"
fetch_blob_sha() {
  case "$1" in
    scripts/check-css.mjs) printf '%s' "$SHA_CHECK_CSS" ;;
    LICENSE) printf '%s' "$SHA_LICENSE" ;;
    PRACTICES.md) printf '%s' "$stub_practices" ;;
    *) return 1 ;;
  esac
}

# A plugin root whose vendored copies are the shipped ones.
REAL_PLUGIN_DIR="$PLUGIN_DIR"
PLUGIN_DIR="$TMP/plugin"
mkdir -p "$PLUGIN_DIR/skills/write-css/vendor"
cp "$REAL_PLUGIN_DIR/skills/write-css/vendor/check-css.mjs" "$REAL_PLUGIN_DIR/skills/write-css/vendor/LICENSE" \
  "$PLUGIN_DIR/skills/write-css/vendor/"

# 1. Upstream and vendored copies at the pin.
out=$(run_check 2>&1)
code=$?
assert_eq "same SHAs: exit 0" 0 "$code"
assert_contains "same SHAs: reports no drift" "$out" "No drift"

# 2. One upstream file changed.
stub_practices="$CHANGED_SHA"
out=$(run_check 2>&1)
code=$?
assert_eq "changed PRACTICES.md: exit 1" 1 "$code"
assert_contains "changed PRACTICES.md: names the file" "$out" "CHANGED    PRACTICES.md"
assert_contains "changed PRACTICES.md: shows the new SHA" "$out" "$CHANGED_SHA"
assert_not_contains "changed PRACTICES.md: LICENSE not flagged" "$out" "CHANGED    LICENSE"
assert_contains "changed PRACTICES.md: compare URL" "$out" \
  "https://github.com/vojtaholik/good-css/compare/b645ab15b9fcd059c0227c21b6a144bb70639f1a...main"
stub_practices="$SHA_PRACTICES"

# 3. The fetch fails.
saved_fetch="$(declare -f fetch_blob_sha)"
fetch_blob_sha() { return 1; }
out=$(run_check 2>&1)
code=$?
assert_eq "fetch failure: exit 2" 2 "$code"

# 3b. An upstream file is gone (404): drift, not unverifiable.
fetch_blob_sha() {
  case "$1" in
    scripts/check-css.mjs) return 3 ;;
    LICENSE) printf '%s' "$SHA_LICENSE" ;;
    PRACTICES.md) printf '%s' "$SHA_PRACTICES" ;;
    *) return 1 ;;
  esac
}
out=$(run_check 2>&1)
code=$?
assert_eq "upstream file gone: exit 1" 1 "$code"
assert_contains "upstream file gone: names the file" "$out" "GONE       scripts/check-css.mjs"
eval "$saved_fetch"

# 4. A vendored copy edited locally, upstream unchanged.
printf '\n// local edit\n' >>"$PLUGIN_DIR/skills/write-css/vendor/check-css.mjs"
out=$(run_check 2>&1)
code=$?
assert_eq "modified vendored file: exit 1" 1 "$code"
assert_contains "modified vendored file: names the copy" "$out" "MODIFIED   skills/write-css/vendor/check-css.mjs"

# 5. A vendored copy missing.
rm "$PLUGIN_DIR/skills/write-css/vendor/LICENSE"
out=$(run_check 2>&1)
code=$?
assert_eq "missing vendored file: exit 1" 1 "$code"
assert_contains "missing vendored file: names the copy" "$out" "MISSING    skills/write-css/vendor/LICENSE"

# 6. Command line.
bash "$SCRIPT" --help >/dev/null 2>&1
assert_eq "--help: exit 0" 0 "$?"
bash "$SCRIPT" --bogus >/dev/null 2>&1
assert_eq "unknown mode: exit 2" 2 "$?"

if ((FAILED)); then
  printf '\n%d check(s) failed.\n' "$FAILED" >&2
  exit 1
fi
printf '\nAll checks passed.\n'
