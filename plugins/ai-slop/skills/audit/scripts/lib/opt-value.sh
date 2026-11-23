# GENERATED from lib/opt-value.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# shellcheck shell=bash
# Exit: 2 (or $OPT_VALUE_EXIT) on a missing, empty or -leading value; OPT_VALUE_STDIN admits a lone -.
require_opt_value() {
  if [[ $# -lt 3 || -z "$3" ]] || [[ "$3" == -* && ! ("$3" == - && -n "${OPT_VALUE_STDIN:-}") ]]; then
    echo "$1: $2 requires a value" >&2
    exit "${OPT_VALUE_EXIT:-2}"
  fi
}
