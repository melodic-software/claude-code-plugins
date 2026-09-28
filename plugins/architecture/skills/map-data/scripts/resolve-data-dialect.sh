#!/usr/bin/env bash
# Resolve diagram_dialect.data from an authoring-formats topic doc.
#
# The ladder the skill restates: an explicit --dialect argument is the caller's
# job. This script is the team-doc rung. A missing doc, a missing key, or a
# value outside mermaid|dbml degrades to mermaid and says why on stderr.
#
# Usage:
#   resolve-data-dialect.sh [--formats <authoring-formats README>]
#   resolve-data-dialect.sh --help
#
# Stdout is exactly mermaid or dbml. Exit 0 always when usage is valid.
# Exit 2 on usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

formats=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --formats)
    [[ $# -ge 2 ]] || {
      printf 'resolve-data-dialect.sh: --formats needs a path\n' >&2
      exit 2
    }
    formats="$2"
    shift 2
    ;;
  *)
    printf 'resolve-data-dialect.sh: unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

default_out() {
  printf 'mermaid\n'
}

if [[ -z "$formats" ]]; then
  printf 'diagram_dialect.data: no authoring-formats doc, default mermaid\n' >&2
  default_out
  exit 0
fi
if [[ ! -f "$formats" ]]; then
  printf 'diagram_dialect.data: no authoring-formats doc at %s, default mermaid\n' "$formats" >&2
  default_out
  exit 0
fi

value="$(
  awk '
    BEGIN { fence = 0; in_key = 0; found = "" }
    $0 ~ /^```/ {
      if (fence) { fence = 0; in_key = 0 } else { fence = 1 }
      next
    }
    fence == 0 { next }
    $0 ~ /^diagram_dialect:[[:space:]]*$/ { in_key = 1; next }
    in_key && $0 ~ /^[^[:space:]#]/ { in_key = 0 }
    in_key && $0 ~ /^[[:space:]]+data:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]+data:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      gsub(/["'\'']/, "", line)
      found = line
      in_key = 0
    }
    END { printf "%s", found }
  ' "$formats"
)"

if [[ -z "$value" ]]; then
  printf 'diagram_dialect.data: absent key, default mermaid\n' >&2
  default_out
  exit 0
fi
if [[ "$value" != "mermaid" && "$value" != "dbml" ]]; then
  printf 'diagram_dialect.data: unrecognized value %s, default mermaid\n' "$value" >&2
  default_out
  exit 0
fi
printf '%s\n' "$value"
exit 0
