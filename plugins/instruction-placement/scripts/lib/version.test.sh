#!/usr/bin/env bash
# Regression tests for lib/version.sh: the plugin's one version comparator
# and the measured-on stamp parser precompute.sh's mechanics line reads.
#
# Fixture strings only: no live `claude` call and no network. One case reads
# the shipped mechanics record, to prove the parser still finds a stamp in it
# after an edit to its citation markers.
# test-scope: plugins/instruction-placement/context/verified-mechanics.md

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=./version.sh
. "$SCRIPT_DIR/version.sh"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
status_of() {
  "$@"
  printf '%s' "$?"
}

# --------------------------------------------------------------------------
# ip_ver_ge / ip_ver_gt
# --------------------------------------------------------------------------
assert_eq "equal versions are >=" "0" "$(status_of ip_ver_ge 2.1.278 2.1.278)"
assert_eq "equal versions are not >" "1" "$(status_of ip_ver_gt 2.1.278 2.1.278)"
assert_eq "a newer third component is >" "0" "$(status_of ip_ver_gt 2.1.296 2.1.278)"
assert_eq "an older third component is not >=" "1" "$(status_of ip_ver_ge 2.1.250 2.1.278)"
assert_eq "the comparison is numeric, not lexical" "0" "$(status_of ip_ver_gt 2.1.1000 2.1.999)"
assert_eq "a newer minor beats a larger third component" "0" "$(status_of ip_ver_gt 2.2.0 2.1.999)"
assert_eq "a leading zero is decimal, not octal" "0" "$(status_of ip_ver_ge 2.1.09 2.1.8)"
assert_eq "a missing component counts as 0" "0" "$(status_of ip_ver_ge 2.1 2.1.0)"
# shellcheck disable=SC2016 # the payload must reach the comparator unexpanded
payload='1+a[$(touch "$TMP/ran")]'
assert_eq "a non-numeric component returns 2" "2" "$(status_of ip_ver_ge "2.1.$payload" 2.1.0)"
assert_eq "and is not evaluated as arithmetic" "absent" \
  "$([[ -e "$TMP/ran" ]] && echo present || echo absent)"
assert_eq "a non-numeric side is not strictly newer" "2" "$(status_of ip_ver_gt 2.1.0 2.x.0)"

# --------------------------------------------------------------------------
# ip_version_in
# --------------------------------------------------------------------------
assert_eq "reads the version off a --version line" "2.1.296" \
  "$(ip_version_in '2.1.296 (Claude Code)')"
assert_eq "an unversioned line yields nothing" "" "$(ip_version_in 'command not found')"

# --------------------------------------------------------------------------
# ip_mechanics_measured_max
# --------------------------------------------------------------------------
cat >"$TMP/record.md" <<'EOF'
| Surface | When |
|---|---|
| A | On read *(doc, measured)* |
| B | On read *(changelog 2.1.288, measured 2.1.268)* |
| C | Never *(doc, measured 2.1.238 and 2.1.278)* |
| D | Write *(changelog 2.1.290)* |
| E | Read *(measured 2.1.250, changelog 2.1.299)* |
EOF
assert_eq "the newest measured stamp wins, and changelog versions never count" "2.1.278" \
  "$(ip_mechanics_measured_max "$TMP/record.md")"

printf '| A | *(measured 2.1.268; Write unmeasured)* |\n' >"$TMP/later-word.md"
assert_eq "a later word ending in measured does not hide the stamp" "2.1.268" \
  "$(ip_mechanics_measured_max "$TMP/later-word.md")"

printf '| A | *(doc)* |\n| B | *(measured)* |\n| C | *(changelog 2.1.288)* |\n' >"$TMP/none.md"
assert_eq "a record with no versioned measurement yields nothing" "" \
  "$(ip_mechanics_measured_max "$TMP/none.md")"
assert_eq "an unreadable record yields nothing" "" \
  "$(ip_mechanics_measured_max "$TMP/absent.md")"

real="$(ip_mechanics_measured_max "$SCRIPT_DIR/../../context/verified-mechanics.md")"
if [[ "$real" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  pass "the shipped record still carries a stamp the parser reads ($real)"
else
  fail "the shipped record still carries a stamp the parser reads" "a version" "${real:-(empty)}"
fi

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
