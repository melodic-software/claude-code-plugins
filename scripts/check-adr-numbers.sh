#!/usr/bin/env bash
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
    printf -v joined '%s, ' "${files[@]}"
    offenders+=("$number: ${joined%, }")
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
