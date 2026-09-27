# shellcheck shell=bash
# Shared option-value guard for the /audit-noise scripts (sourceable; not
# invoked directly).

# require_opt_value <script> <option> [value ...]: refuse an option whose value
# is missing, empty, or another option. The script name is a parameter because
# each caller names itself in its own diagnostics; exit 2 is the usage code both
# callers document in their own `Exit:` line.
require_opt_value() {
  local script="$1" opt="$2"
  if [[ $# -lt 3 || -z "${3:-}" || "$3" == -* ]]; then
    echo "$script: $opt requires a value" >&2
    exit 2
  fi
}
