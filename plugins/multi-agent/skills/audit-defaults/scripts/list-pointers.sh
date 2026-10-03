#!/usr/bin/env bash
# list-pointers.sh [--json] [<role>|fanout]: print every bundled default's
# provenance as TSV (owner, key, value): pointer*, as_of and recheck per role
# and for the fan-out guard, then the resolved values those pointers back. With
# an owner, both blocks keep only that owner's rows. --json prints both blocks
# as one array of {owner, key, value} for the drift-audit workflow's
# args.pointers; a value row's key is its full dotted key.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-roles.sh"
JSON=0
if [[ "${1:-}" == --json ]]; then
  JSON=1
  shift
fi
OWNER="${1:-}"

pointers="$("$RESOLVER" pointers)" || exit
if [[ -n "$OWNER" ]] && ! awk -F '\t' -v o="$OWNER" '$1 == o { found = 1 } END { exit !found }' <<<"$pointers"; then
  printf 'list-pointers: unknown owner %s (valid: %s)\n' "$OWNER" \
    "$(cut -f1 <<<"$pointers" | sort -u | tr '\n' ' ')" >&2
  exit 2
fi
pointer_rows="$(awk -F '\t' -v o="$OWNER" 'o == "" || $1 == o' <<<"$pointers")"
# A role's values are roles.<role>.*; the fan-out guard's are fanout.* and frontier.
value_rows="$(awk -f "$SCRIPT_DIR/../../../scripts/yaml-subset.awk" "$SCRIPT_DIR/../../../reference/defaults.yaml" |
  awk -F '\t' -v o="$OWNER" '
    $1 ~ /(pointer[^.]*|as_of|recheck)$/ { next }
    o == "" { print; next }
    o == "fanout" && ($1 ~ /^fanout\./ || $1 == "frontier") { print; next }
    index($1, "roles." o ".") == 1 { print }')"

if ((JSON == 0)); then
  printf '%s\n\n%s\n' "$pointer_rows" "$value_rows"
  exit 0
fi

{
  printf '%s\n' "$pointer_rows"
  awk -F '\t' '
    $1 ~ /^fanout\./ || $1 == "frontier" { print "fanout\t" $0; next }
    $1 ~ /^roles\.[^.]+\./ { split($1, p, "."); print p[2] "\t" $0 }' <<<"$value_rows"
} | awk -F '\t' '
  function esc(s) {
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s)
    return s
  }
  NF >= 3 {
    printf "%s{\"owner\":\"%s\",\"key\":\"%s\",\"value\":\"%s\"}", (n++ ? ",\n " : "["), esc($1), esc($2), esc($3)
  }
  END { print (n ? "]" : "[]") }'
