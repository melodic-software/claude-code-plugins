#!/usr/bin/env bash
# list-pointers.sh [<role>|fanout]: print every bundled default's provenance
# as TSV (owner, key, value): pointer*, as_of and recheck per role and for the
# fan-out guard, then the resolved values those pointers back. With an owner,
# both blocks keep only that owner's rows.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-roles.sh"
OWNER="${1:-}"

pointers="$("$RESOLVER" pointers)" || exit
if [[ -n "$OWNER" ]] && ! awk -F '\t' -v o="$OWNER" '$1 == o { found = 1 } END { exit !found }' <<<"$pointers"; then
  printf 'list-pointers: unknown owner %s (valid: %s)\n' "$OWNER" \
    "$(cut -f1 <<<"$pointers" | sort -u | tr '\n' ' ')" >&2
  exit 2
fi
awk -F '\t' -v o="$OWNER" 'o == "" || $1 == o' <<<"$pointers"
printf '\n'
# A role's values are roles.<role>.*; the fan-out guard's are fanout.* and frontier.
awk -f "$SCRIPT_DIR/../../../scripts/yaml-subset.awk" "$SCRIPT_DIR/../../../reference/defaults.yaml" |
  awk -F '\t' -v o="$OWNER" '
    $1 ~ /(pointer[^.]*|as_of|recheck)$/ { next }
    o == "" { print; next }
    o == "fanout" && ($1 ~ /^fanout\./ || $1 == "frontier") { print; next }
    index($1, "roles." o ".") == 1 { print }'
