#!/usr/bin/env bash
set -uo pipefail

self=estimate-run.sh
usage() {
  printf 'usage: %s --mutants <n> --seconds <s>\n' "$self" >&2
  exit 2
}

n="" s=""
while (($#)); do
  case "$1" in
  --mutants)
    (($# >= 2)) && [[ -z "$n" ]] || usage
    n="$2"
    shift 2
    ;;
  --seconds)
    (($# >= 2)) && [[ -z "$s" ]] || usage
    s="$2"
    shift 2
    ;;
  *) usage ;;
  esac
done
[[ -n "$n" && -n "$s" ]] || usage

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
