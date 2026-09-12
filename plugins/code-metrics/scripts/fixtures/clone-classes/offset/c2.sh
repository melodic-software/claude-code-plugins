# shellcheck shell=bash
# Offset fixture: the shared fragment begins on line 4 of this copy, one
# line lower than in the first copy, so no instance range aligns with it.
HARVEST_LABEL="harvest"

announce_start() {
  local subject="$1"
  printf 'start %s %s\n' "$HARVEST_LABEL" "$subject"
}

announce_finish() {
  local subject="$1"
  local outcome="${2:-unknown}"
  printf 'finish %s %s %s\n' "$HARVEST_LABEL" "$subject" "$outcome"
}

collect_orchard() {
  local basket="$1"
  shift
  local apple
  for apple in "$@"; do
    if [[ -z "$apple" ]]; then
      continue
    fi
    printf '%s/%s\n' "$basket" "$apple"
  done
}

measure_basket() {
  local basket="$1"
  if [[ -d "$basket" ]]; then
    find "$basket" -type f | wc -l
    return 0
  fi
  printf '0\n'
  return 1
}

announce_finish "offset-two" "done"
