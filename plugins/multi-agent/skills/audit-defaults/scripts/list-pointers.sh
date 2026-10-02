#!/usr/bin/env bash
# list-pointers.sh: print every bundled default's provenance as TSV
# (owner, key, value): pointer*, as_of and recheck per role and for the
# fan-out guard, then the resolved values those pointers back.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-roles.sh"

"$RESOLVER" pointers || exit
printf '\n'
awk -F '\t' '$1 !~ /(pointer[^.]*|as_of|recheck)$/' \
  < <(awk -f "$SCRIPT_DIR/../../../scripts/yaml-subset.awk" "$SCRIPT_DIR/../../../reference/defaults.yaml")
