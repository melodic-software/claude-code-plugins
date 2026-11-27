# shellcheck shell=bash

SNAPSHOT_ORDER=()

snapshot_ledger_load() {
  local __sl_labels=""
  __sl_labels=$(jq -r '.[] | .snapshot // empty' "$1" 2>/dev/null) && [[ -n "$__sl_labels" ]] || return 1
  mapfile -t SNAPSHOT_ORDER <<<"${__sl_labels//$'\r'/}"
}

snapshot_file() { printf -v "$1" '%s' "${RUN_DIR:?}/$2.$3.json"; }

snapshot_latest() {
  local __sl_i
  printf -v "$1" '%s' ""
  for ((__sl_i = ${#SNAPSHOT_ORDER[@]} - 1; __sl_i >= 0; __sl_i--)); do
    if [[ -f "$RUN_DIR/${SNAPSHOT_ORDER[__sl_i]}.$2.json" ]]; then
      printf -v "$1" '%s' "$RUN_DIR/${SNAPSHOT_ORDER[__sl_i]}.$2.json"
      return 0
    fi
  done
  return 1
}

snapshot_as_of() {
  local __sl_label __sl_seen=0
  printf -v "$1" '%s' ""
  for __sl_label in "${SNAPSHOT_ORDER[@]}"; do
    [[ "$__sl_label" == "$3" ]] && __sl_seen=1
    ((__sl_seen == 1)) && [[ -f "$RUN_DIR/$__sl_label.$2.json" ]] || continue
    printf -v "$1" '%s' "$RUN_DIR/$__sl_label.$2.json"
    return 0
  done
  return 1
}

snapshot_intervals() {
  local __sl_label __sl_prev="" __sl_pairs=""
  for __sl_label in "${SNAPSHOT_ORDER[@]}"; do
    [[ -f "$RUN_DIR/$__sl_label.$2.json" ]] || continue
    [[ -z "$__sl_prev" ]] || __sl_pairs+="$__sl_prev $__sl_label"$'\n'
    __sl_prev="$__sl_label"
  done
  printf -v "$1" '%s' "$__sl_pairs"
}
