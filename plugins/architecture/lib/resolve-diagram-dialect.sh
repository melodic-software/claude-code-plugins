#!/usr/bin/env bash
# Resolve diagram_dialect.<kind> from an authoring-formats topic doc.
#
# This script is the team-doc rung of the authoring-formats ladder. An explicit
# --dialect argument on the skill invocation is the caller's job.
#
#   data    mermaid | dbml. A missing doc, key, or value outside the set
#           degrades to the default mermaid.
#   system  likec4 | c4-plantuml. No default: a missing doc, key, or value
#           outside the set (mermaid included, which the convention refuses)
#           prints none, meaning emit no C4 view.
#
# Usage:
#   resolve-diagram-dialect.sh --kind data|system [--formats <authoring-formats README>]
#   resolve-diagram-dialect.sh --help
#
# Stdout is one of mermaid, dbml, likec4, c4-plantuml, none. The cause of any
# fallback goes to stderr. Exit 0 when usage is valid, 2 on usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'resolve-diagram-dialect.sh: %s\n' "$1" >&2
  exit 2
}

kind=""
formats=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --kind)
    [[ $# -ge 2 ]] || die "--kind needs data or system"
    kind="$2"
    shift 2
    ;;
  --formats)
    [[ $# -ge 2 ]] || die "--formats needs a path"
    formats="$2"
    shift 2
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

case "$kind" in
data) fallback="mermaid" allowed=" mermaid dbml " ;;
system) fallback="none" allowed=" likec4 c4-plantuml " ;;
*) die "--kind must be data or system" ;;
esac

fall_back() {
  if [[ "$kind" == "system" ]]; then
    printf 'diagram_dialect.system: %s, unset (no C4 view emitted)\n' "$1" >&2
  else
    printf 'diagram_dialect.%s: %s, default %s\n' "$kind" "$1" "$fallback" >&2
  fi
  printf '%s\n' "$fallback"
  exit 0
}

[[ -n "$formats" ]] || fall_back "no authoring-formats doc"
[[ -f "$formats" ]] || fall_back "no authoring-formats doc at $formats"

value="$(
  KIND="$kind" awk '
    BEGIN { fence = 0; in_key = 0; found = ""; kind = ENVIRON["KIND"] }
    $0 ~ /^```/ {
      if (fence) { fence = 0; in_key = 0 } else { fence = 1 }
      next
    }
    fence == 0 { next }
    $0 ~ /^diagram_dialect:[[:space:]]*$/ { in_key = 1; next }
    in_key && $0 ~ /^[^[:space:]#]/ { in_key = 0 }
    in_key && $0 ~ ("^[[:space:]]+" kind ":") {
      line = $0
      sub("^[[:space:]]+" kind ":[[:space:]]*", "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      gsub(/["'\'']/, "", line)
      found = line
    }
    END { printf "%s", found }
  ' "$formats"
)"

[[ -n "$value" ]] || fall_back "absent key"
[[ "$allowed" == *" $value "* ]] || fall_back "unrecognized value $value"
printf '%s\n' "$value"
