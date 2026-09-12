# shellcheck shell=bash
# Fixture source for the code-metrics duplication suites: a helper vendored
# byte-identical into two sibling plugin directories, standing in for a
# repository that deliberately replicates one path across its plugins. Never
# executed, so it carries no shebang and no exec bit; kept lint-clean on
# purpose. The copy under the sibling directory is byte-for-byte this file.

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
