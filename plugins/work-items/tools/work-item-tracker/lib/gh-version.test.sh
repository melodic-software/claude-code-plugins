#!/usr/bin/env bash
# Version-guard boundary for the native sub-issue/dependency surface: below
# 2.94 is refused, 2.94 and above is accepted. Stub gh on PATH; no network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-version.sh
source "$SCRIPT_DIR/gh-version.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

STUB_BIN="$(mktemp -d)"
trap 'rm -rf "$STUB_BIN"' EXIT

cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh version %s (test)\n' "${GH_STUB_VERSION:?}"
EOF
chmod +x "$STUB_BIN/gh"

run_at() {
  local ver="$1"
  GH_STUB_VERSION="$ver" PATH="$STUB_BIN:$PATH" wit_gh_has_native_surface
  printf '%s\n' "$?"
}

assert_eq "2.45 (observed cloud gh) is below the floor" "1" "$(run_at 2.45.0)"
assert_eq "2.93 is below the floor" "1" "$(run_at 2.93.0)"
assert_eq "2.94 meets the floor" "0" "$(run_at 2.94.0)"
assert_eq "2.95 is above the floor" "0" "$(run_at 2.95.1)"
assert_eq "3.0 (next major) meets the floor" "0" "$(run_at 3.0.0)"

assert_eq "raw version from 2.45 stub" "2.45" \
  "$(GH_STUB_VERSION=2.45.0 PATH="$STUB_BIN:$PATH" wit_gh_version_raw)"
assert_eq "raw version from 2.94 stub" "2.94" \
  "$(GH_STUB_VERSION=2.94.0 PATH="$STUB_BIN:$PATH" wit_gh_version_raw)"

UNPARSEABLE="$STUB_BIN/unparseable"
mkdir -p "$UNPARSEABLE"
cat >"$UNPARSEABLE/gh" <<'EOF'
#!/usr/bin/env bash
printf 'not a version string\n'
EOF
chmod +x "$UNPARSEABLE/gh"
PATH="$UNPARSEABLE:$PATH" wit_gh_has_native_surface
assert_eq "unparseable gh --version fails closed" "1" "$?"

NOGH="$(mktemp -d)"
trap 'rm -rf "$STUB_BIN" "$NOGH"' EXIT
PATH="$NOGH" wit_gh_has_native_surface
assert_eq "missing gh fails closed" "1" "$?"

[[ $FAILED -eq 0 ]] || exit 1
