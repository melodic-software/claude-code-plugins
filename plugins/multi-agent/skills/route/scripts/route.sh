#!/usr/bin/env bash
# route.sh <role|all> [workload] [session=<alias>]
# Translates the skill's arguments for scripts/resolve-roles.sh and runs it:
# the first bare argument is the role, the second the workload.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-roles.sh"

pass=()
bare=0
value=0
for a in "$@"; do
  if ((value)); then
    pass+=("$a") value=0
    continue
  fi
  case "$a" in
  session=*) [[ -n "${a#session=}" ]] && pass+=(--session-model "${a#session=}") ;;
  --workload | --session-model | --root | --home | --defaults) pass+=("$a") value=1 ;;
  -*) pass+=("$a") ;;
  *)
    bare=$((bare + 1))
    if ((bare == 2)); then pass+=(--workload "$a"); else pass+=("$a"); fi
    ;;
  esac
done
exec "$RESOLVER" "${pass[@]+"${pass[@]}"}"
