#!/usr/bin/env bash
# Check that every tracked *.test.sh that creates a temp path with mktemp also
# installs a `trap ... EXIT` to remove it.
#
#   scripts/check-test-tmp-cleanup.sh          discover: list every offender
#   scripts/check-test-tmp-cleanup.sh --check  same, explicit form matching the
#                                              sibling gates (exit 1 on any offender)
#
# The rule: a suite whose non-comment lines mention `mktemp` and none of whose
# non-comment lines match `trap ... EXIT` leaves its fixtures behind on every
# run, and on an early exit or a failed assertion. An offender is a fail unless
# it is listed in scripts/test-tmp-cleanup-baseline.txt, the known offenders.
# The baseline is a ratchet: an entry whose file is gone or no longer offends
# is a fail too, so the list only shrinks. Fix a suite by adding the trap, then
# delete its baseline line. Never add a suite to the baseline: give it the trap
# instead.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one finding per line on stderr, the clean-run statement on
# stdout. Exit: 0 clean, 1 any offender, 2 environment or usage (git or awk
# missing, bad argument, unreadable baseline).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

for tool in git awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'check-test-tmp-cleanup: %s is required\n' "$tool" >&2
    exit 2
  fi
done

BASELINE="${TEST_TMP_CLEANUP_BASELINE:-scripts/test-tmp-cleanup-baseline.txt}"
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
baseline=()
# shellcheck disable=SC2310  # the non-zero return IS the handled case
read_list::into baseline "$BASELINE" --comments inline || exit 2

# offends <file>: true when the file mentions mktemp and has no EXIT trap,
# ignoring comment lines.
offends() {
  awk '
    /^[[:space:]]*#/ { next }
    /mktemp/ { made = 1 }
    /trap[^#]*EXIT/ { trapped = 1 }
    END { exit !(made && !trapped) }
  ' "$1"
}

in_baseline() {
  local one
  for one in ${baseline+"${baseline[@]}"}; do
    [[ "$one" == "$1" ]] && return 0
  done
  return 1
}

findings=()
tracked=()
while IFS= read -r -d '' path; do
  tracked+=("$path")
  # shellcheck disable=SC2310  # offends and in_baseline only test; nothing inside can fail the script
  if offends "$path" && ! in_baseline "$path"; then
    findings+=("$path: mktemp without a trap ... EXIT; add the trap")
  fi
done < <(git ls-files -z -- '*.test.sh')

for entry in ${baseline+"${baseline[@]}"}; do
  if [[ ! -f "$entry" ]]; then
    findings+=("$entry: $BASELINE lists it, but the file does not exist; remove the entry")
    continue
  fi
  # shellcheck disable=SC2310  # offends only tests; nothing inside can fail the script
  if ! offends "$entry"; then
    findings+=("$entry: $BASELINE lists it, but it no longer offends; remove the entry")
  fi
done

if ((${#findings[@]} == 0)); then
  printf 'check-test-tmp-cleanup: %d tracked *.test.sh checked; every mktemp user traps EXIT or is baselined.\n' "${#tracked[@]}"
  exit 0
fi

printf '%s\n' "${findings[@]}" | sort -u >&2
printf 'check-test-tmp-cleanup: %d finding(s); see the header of scripts/%s.\n' "${#findings[@]}" "${0##*/}" >&2
exit 1
