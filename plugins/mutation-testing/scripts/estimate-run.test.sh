#!/usr/bin/env bash
# Black-box contract test for estimate-run.sh.
#
# Self-contained and cwd-independent; writes nothing. Every expected line below
# is worked out by hand from the arithmetic in the script's header, not from
# running the script.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/estimate-run.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

out=""
code=0
est() {
  out="$(bash "$SUT" "$@" 2>/dev/null)"
  code=$?
}

expect() { # expect <label> <line>: exit 0 and exactly that line on stdout
  if [[ "$code" -eq 0 && "$out" == "$2" ]]; then pass "$1"; else fail "$1 - want exit 0 and [$2], got exit $code: [$out]"; fi
}

refuse() { # refuse <label>: exit 2 and nothing on stdout
  if [[ "$code" -eq 2 && -z "$out" ]]; then pass "$1 refuses"; else fail "$1 - want exit 2 and no stdout, got exit $code: [$out]"; fi
}

est --mutants 120 --seconds 45
expect "120 mutants at 45s" "Estimated wall-clock: 1h 30m (120 mutants x 45s per build-and-test)"
est --seconds 45 --mutants 120
expect "the flags in either order" "Estimated wall-clock: 1h 30m (120 mutants x 45s per build-and-test)"
est --mutants 0 --seconds 45
expect "zero mutants" "Estimated wall-clock: 0h 0m (0 mutants x 45s per build-and-test)"

# A fractional time: 7 x 2.5 is 17.5s, which rounds up to a minute; 24 x 2.5
# is exactly 60s and stays one minute; 25 x 2.5 is 62.5s and goes to two.
est --mutants 7 --seconds 2.5
expect "a fractional time rounds up" "Estimated wall-clock: 0h 1m (7 mutants x 2.5s per build-and-test)"
est --mutants 24 --seconds 2.5
expect "an exact minute is not rounded up" "Estimated wall-clock: 0h 1m (24 mutants x 2.5s per build-and-test)"
est --mutants 25 --seconds 2.5
expect "past a minute rounds to the next" "Estimated wall-clock: 0h 2m (25 mutants x 2.5s per build-and-test)"
est --mutants 1 --seconds 0.001
expect "one millisecond of work is a minute" "Estimated wall-clock: 0h 1m (1 mutants x 0.001s per build-and-test)"
est --mutants 3 --seconds 1200.5
expect "3601.5s is 1h 1m" "Estimated wall-clock: 1h 1m (3 mutants x 1200.5s per build-and-test)"
est --mutants 1500 --seconds 180
expect "hours past a day stay hours" "Estimated wall-clock: 75h 0m (1500 mutants x 180s per build-and-test)"

# A leading zero is decimal, not octal: 010 mutants at 60s is 10 minutes.
est --mutants 010 --seconds 60
expect "a leading zero is decimal" "Estimated wall-clock: 0h 10m (010 mutants x 60s per build-and-test)"
est --mutants 9 --seconds 08.5
expect "a leading zero in the seconds is decimal" "Estimated wall-clock: 0h 2m (9 mutants x 08.5s per build-and-test)"

est
refuse "no arguments"
est --mutants 120
refuse "a missing --seconds"
est --seconds 45
refuse "a missing --mutants"
est --mutants 120 --seconds
refuse "a flag with no value"
est --mutants 1 --mutants 2 --seconds 45
refuse "a repeated flag"
est --mutants 120 --seconds 45 --max 5
refuse "an unknown flag"
est --mutants 1.5 --seconds 45
refuse "a fractional mutant count"
est --mutants -3 --seconds 45
refuse "a negative mutant count"
est --mutants 1234567890 --seconds 45
refuse "a ten-digit mutant count"
est --mutants 120 --seconds 2.5000
refuse "four decimal places"
est --mutants 120 --seconds .5
refuse "a decimal with no whole part"
est --mutants 120 --seconds abc
refuse "a non-number time"
est --mutants 120 --seconds 0
refuse "a zero time"
est --mutants 120 --seconds 0.000
refuse "a zero decimal time"

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'all passed\n'
