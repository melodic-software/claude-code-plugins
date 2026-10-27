#!/usr/bin/env bash
# estimate-run.sh --mutants <n> --seconds <s>: the audit's wall-clock estimate.
#
# Prints one line:
#
#   Estimated wall-clock: <h>h <m>m (<n> mutants x <s>s per build-and-test)
#
# <n> is the mutant count, a whole number. <s> is the timed wall-clock of one
# build plus test run of the selected scope, above zero, a whole number or a
# decimal with up to three places. Both are printed as given and read as
# decimal, a leading zero included. The total is <n> x <s>
# rounded up to the next whole minute, so a run with any work never reads as
# 0h 0m. <s> is scaled to whole milliseconds, so the arithmetic is integer and
# exact, with no float error to push an exact minute up to the next one.
#
# Exit 0: printed. 2: usage error, a missing, repeated or malformed value, or
# a zero <s>; nothing is printed on stdout.
set -uo pipefail

self=estimate-run.sh
usage() {
  printf 'usage: %s --mutants <n> --seconds <s>\n' "$self" >&2
  exit 2
}

n="" s=""
while (($#)); do
  case "$1" in
  --mutants | --seconds)
    (($# >= 2)) || usage
    if [[ "$1" == --mutants ]]; then
      [[ -z "$n" ]] || usage
      n="$2"
    else
      [[ -z "$s" ]] || usage
      s="$2"
    fi
    shift 2
    ;;
  *) usage ;;
  esac
done
[[ -n "$n" && -n "$s" ]] || usage

# The digit caps keep <n> x <s in ms> inside 64-bit arithmetic.
if [[ ! "$n" =~ ^[0-9]{1,9}$ ]]; then
  printf '%s: --mutants must be a whole number of at most 9 digits, got %s\n' "$self" "$n" >&2
  exit 2
fi
if [[ ! "$s" =~ ^([0-9]{1,6})(\.([0-9]{1,3}))?$ ]]; then
  printf '%s: --seconds must be a number with at most 6 digits and 3 decimal places, got %s\n' "$self" "$s" >&2
  exit 2
fi
frac="${BASH_REMATCH[3]}000"
ms=$((10#${BASH_REMATCH[1]} * 1000 + 10#${frac:0:3}))
if ((ms == 0)); then
  printf '%s: --seconds is zero; a build-and-test that took no time was not timed\n' "$self" >&2
  exit 2
fi

minutes=$(((10#$n * ms + 59999) / 60000))
printf 'Estimated wall-clock: %dh %dm (%s mutants x %ss per build-and-test)\n' \
  $((minutes / 60)) $((minutes % 60)) "$n" "$s"
