#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
Resolve diagram_dialect.<kind> from an authoring-formats topic doc.
Usage: resolve-diagram-dialect.sh --kind data|system [--formats <authoring-formats README>]
  --kind     data (mermaid | dbml, default mermaid) or system (likec4 | c4-plantuml, else none)
  --formats  the authoring-formats README to read
Prints mermaid, dbml, likec4, c4-plantuml or none; the cause of any fallback goes to stderr.
Exit: 0 on valid usage, 2 on usage.
EOF
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
