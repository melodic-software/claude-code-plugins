#!/usr/bin/env bash
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
  --workload | --session-model | --root | --home | --user-file | --defaults) pass+=("$a") value=1 ;;
  -*) pass+=("$a") ;;
  *) if ((++bare == 2)); then pass+=(--workload "$a"); else pass+=("$a"); fi ;;
  esac
done
exec "$RESOLVER" "${pass[@]+"${pass[@]}"}"
