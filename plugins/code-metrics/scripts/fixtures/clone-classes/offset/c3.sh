# shellcheck shell=bash
# Offset fixture: this copy carries only the first part of the shared
# fragment, beginning on line 5, so the range it shares with the first copy
# is shorter than the range the first and second copies share. The two pairs
# jscpd reports therefore name the first copy with two different ranges and
# stay two clone groups: the merge joins pairs on an identical instance, not
# on an overlapping one.
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

weigh_basket() {
  local basket="$1"
  local weight="${2:-0}"
  printf 'weigh %s %s\n' "$basket" "$weight"
}

weigh_basket "offset-three" 7
