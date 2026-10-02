#!/usr/bin/env bash
# route.sh <role|all> [code|research|mechanical] [session=<alias>]
# Translates the skill's arguments for scripts/resolve-roles.sh and runs it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-roles.sh"

pass=()
for a in "$@"; do
  case "$a" in
  session=*) [[ -n "${a#session=}" ]] && pass+=(--session-model "${a#session=}") ;;
  code | research | mechanical) pass+=(--workload "$a") ;;
  *) pass+=("$a") ;;
  esac
done
exec "$RESOLVER" "${pass[@]+"${pass[@]}"}"
