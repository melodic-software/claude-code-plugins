#!/usr/bin/env bash
# Reader-interface tests for lib/cascade-read.sh. Assertion helpers are local.
# cascade::* assigns through printf -v and namerefs, which shellcheck cannot see.
# shellcheck disable=SC2154
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cascade-read.sh
source "$SCRIPT_DIR/lib/cascade-read.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "cascade-read.test.sh: jq is required" >&2
  exit 2
fi

write_layer() {
  printf '%s\n' "$2" >"$1"
}

# --- scalar -----------------------------------------------------------------
A="$TEST_TMPDIR/a.json"
B="$TEST_TMPDIR/b.json"
write_layer "$A" '{ "n": "1" }'
write_layer "$B" '{ "n": "2" }'
cascade::scalar got '.n' "$A" "$B"
assert_eq "scalar: later layer wins" "$got" "2"

write_layer "$B" '{ "other": "9" }'
cascade::scalar got '.n' "$A" "$B"
assert_eq "scalar: a layer missing the key keeps the earlier value" "$got" "1"

write_layer "$B" '{ "n": "9" } trailing'
cascade::scalar got '.n' "$A" "$B"
assert_eq "scalar: a truncated layer is refused whole" "$got" "1"

# --- list -------------------------------------------------------------------
items=()
write_layer "$A" '{ "items": ["one", "two words"] }'
write_layer "$B" '{ "items": ["later"] }'
cascade::list items items "$A" "$B"
assert_eq "list: later layer replaces" "${items[*]}" "later"
assert_eq "list: cascade_list_layer names the winning layer" "$cascade_list_layer" "$B"

write_layer "$B" '{ "other": [] }'
cascade::list items items "$A" "$B"
assert_eq "list: a missing key keeps the inherited list" "${items[*]}" "one two words"
assert_eq "list: elements keep internal spaces" "${items[1]}" "two words"
assert_eq "list: cascade_list_layer skips a layer without the key" "$cascade_list_layer" "$A"

# shellcheck disable=SC2034  # filled through a nameref
none=()
cascade::list none absent "$A" "$B"
assert_eq "list: cascade_list_layer is empty when no layer defines the key" "$cascade_list_layer" ""

write_layer "$B" '{ "items": [] }'
cascade::list items items "$A" "$B"
assert_eq "list: an explicit empty array clears the inherited list" "${items[*]-}" ""

write_layer "$A" '{ "items": ["kept"] }'
write_layer "$B" '{ "items": ["dropped"] } trailing'
cascade::list items items "$A" "$B"
assert_eq "list: a truncated layer is refused whole" "${items[*]}" "kept"

# --- per-slug map -----------------------------------------------------------
declare -A slugs=()
write_layer "$A" '{ "paths": { "rule-a": ["keep/**"], "rule-b": ["old/**"] } }'
write_layer "$B" '{ "paths": { "rule-b": ["new/**"] } }'
cascade::slug_map slugs paths "$A" "$B"
assert_eq "slug map: an unmentioned slug keeps its globs" "${slugs[rule-a]}" "keep/**"
assert_eq "slug map: a later slug replaces only itself" "${slugs[rule-b]}" "new/**"

write_layer "$B" '{ "paths": { "rule-a": [] } }'
cascade::slug_map slugs paths "$A" "$B"
if [[ -v slugs[rule-a] ]]; then
  fail "slug map: an explicit empty array clears the slug" "unset" "set (${slugs[rule-a]})"
else
  pass "slug map: an explicit empty array clears the slug"
fi
assert_eq "slug map: clearing one slug leaves the other" "${slugs[rule-b]}" "old/**"

write_layer "$A" '{ "paths": { "rule-a": ["safe/**"] } }'
write_layer "$B" '{ "paths": { "rule-a": ["bad/**"], "rule-c": ["also/**"] } } trailing'
declare -A slugs=()
cascade::slug_map slugs paths "$A" "$B"
assert_eq "slug map: a truncated layer applies no entry" "${slugs[rule-a]}" "safe/**"
if [[ -v slugs[rule-c] ]]; then
  fail "slug map: a truncated layer does not add a later entry" "unset" "set"
else
  pass "slug map: a truncated layer does not add a later entry"
fi

# --- encoding, once, across every shape ------------------------------------
# A jq that terminates lines with CR (the Windows build) must yield the same
# effective value as LF jq. The shim is the reader's input, not the JSON file.
REAL_JQ="$(command -v jq)"
SHIM="$TEST_TMPDIR/bin"
mkdir -p "$SHIM"
cat >"$SHIM/jq" <<EOF
#!/usr/bin/env bash
"$REAL_JQ" "\$@" | awk '{ printf "%s\r\n", \$0 }'
exit "\${PIPESTATUS[0]}"
EOF
chmod +x "$SHIM/jq"

write_layer "$A" '{ "n": "3.0", "items": ["glob/**", "two words"], "paths": { "rule-a": ["quirks/**"] } }'
write_layer "$B" '{ "n": "4.0", "items": ["overlay/**"], "paths": { "rule-a": ["later/**"] } }'

cascade::scalar lf_scalar '.n' "$A" "$B"
items=()
cascade::list items items "$A" "$B"
lf_list="${items[*]}"
declare -A lf_slugs=()
cascade::slug_map lf_slugs paths "$A" "$B"
lf_slug="${lf_slugs[rule-a]}"

hash -r
PATH="$SHIM:$PATH"
cascade::scalar cr_scalar '.n' "$A" "$B"
items=()
cascade::list items items "$A" "$B"
cr_list="${items[*]}"
declare -A cr_slugs=()
cascade::slug_map cr_slugs paths "$A" "$B"
cr_slug="${cr_slugs[rule-a]}"
hash -r

assert_eq "crlf jq: scalar matches the LF read" "$cr_scalar" "$lf_scalar"
assert_eq "crlf jq: list matches the LF read" "$cr_list" "$lf_list"
assert_eq "crlf jq: slug map matches the LF read" "$cr_slug" "$lf_slug"

if [[ "$FAILED" -ne 0 ]]; then
  printf 'Result: %s failed\n' "$FAILED" >&2
  exit 1
fi
printf 'Result: all passed\n'
