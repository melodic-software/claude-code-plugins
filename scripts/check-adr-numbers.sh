#!/usr/bin/env bash
# Check that every ADR under docs/adr/ carries a number no other record uses.
#
#   scripts/check-adr-numbers.sh          discover: list every offender
#   scripts/check-adr-numbers.sh --check  same, explicit form matching the
#                                         sibling gates (exit 1 on any offender)
#
# The rule: the four-digit prefix of each `docs/adr/NNNN-*` file names one
# record. A prefix carried by two or more files is an offender unless every one
# of those files is listed in scripts/adr-numbers-baseline.txt, the pairs that
# merged before this gate existed. The baseline is stale-guarded: an entry whose
# file is gone, or whose number no longer collides, is an offender too, so an
# exemption cannot outlive its pair.
#
# WHY. Two branches that each compute "highest plus one" against the same base
# both merge, and the repository gains a second record under one number. The
# existing pairs stay: renumbering breaks every inbound link, and the duplicate
# is a fact about the repository's history (the architecture:record-decision
# skill's gotchas state the same posture). This gate stops the next pair. A
# baseline keyed on file names rather than numbers means a third record on a
# baselined number still fails.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one `NNNN: file, file` finding per offending number on stderr,
# the clean-run statement on stdout. Exit: 0 clean, 1 any offender, 2
# environment or usage (bad argument, unreadable baseline, malformed entry).
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

BASELINE="${ADR_NUMBERS_BASELINE:-scripts/adr-numbers-baseline.txt}"
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
baseline=()
# shellcheck disable=SC2310  # the non-zero return IS the handled case
read_list::into baseline "$BASELINE" --comments inline || exit 2
for entry in ${baseline+"${baseline[@]}"}; do
  if [[ ! "$entry" =~ ^[0-9]{4}-[^/]+$ ]]; then
    printf 'check-adr-numbers: %s: %s is not an ADR basename (NNNN-<slug>)\n' "$BASELINE" "$entry" >&2
    exit 2
  fi
done

records=()
if [[ -d docs/adr ]]; then
  for path in docs/adr/[0-9][0-9][0-9][0-9]-*; do
    [[ -f "$path" ]] && records+=("${path##*/}")
  done
fi

in_baseline() {
  local one
  for one in ${baseline+"${baseline[@]}"}; do
    [[ "$one" == "$1" ]] && return 0
  done
  return 1
}

dup_numbers=""
if ((${#records[@]} > 0)); then
  dup_numbers="$(for r in "${records[@]}"; do printf '%s\n' "${r:0:4}"; done | sort | uniq -d)"
fi

offenders=()
for number in $dup_numbers; do
  files=()
  exempt=1
  for r in "${records[@]}"; do
    [[ "${r:0:4}" == "$number" ]] || continue
    files+=("docs/adr/$r")
    # shellcheck disable=SC2310  # in_baseline only compares strings; nothing inside it can fail
    in_baseline "$r" || exempt=""
  done
  if [[ -z "$exempt" ]]; then
    joined="${files[0]}"
    for f in "${files[@]:1}"; do joined="$joined, $f"; done
    offenders+=("$number: $joined")
  fi
done

for entry in ${baseline+"${baseline[@]}"}; do
  if [[ ! -f "docs/adr/$entry" ]]; then
    offenders+=("${entry:0:4}: $BASELINE lists docs/adr/$entry, which does not exist; remove the entry")
  elif ! grep -qxF "${entry:0:4}" <<<"$dup_numbers"; then
    offenders+=("${entry:0:4}: $BASELINE lists docs/adr/$entry, whose number no longer collides; remove the entry")
  fi
done

if ((${#offenders[@]} == 0)); then
  printf 'check-adr-numbers: every ADR number under docs/adr/ is unique or a baselined pair.\n'
  exit 0
fi

printf '%s\n' "${offenders[@]}" | sort -u >&2
printf 'check-adr-numbers: %d offender(s); give the new record the next free number (see the header of %s).\n' \
  "${#offenders[@]}" "scripts/${0##*/}" >&2
exit 1
