#!/usr/bin/env bash
# Print the container label a decision map carries: `tracker.config.container_label`
# from <home>/work-items.yaml, else the shipped default `work-map`.
#
# The read follows the work-item tracker seam's binding rules (work-items CONTRACT.md,
# "Setup (binding file)" and "Containers and state"): the convention home comes from
# the pointer region (default docs/conventions when the repository binds none), the
# file parses with the repository's one YAML subset parser, and an absent or empty key
# takes the default. It uses this plugin's generated copies of the resolver and parser.
#
# Usage: container-label.sh [--root <repo>]
#
# Output: the label on stdout, exit 0. On a configuration error, one line starting
# `ERROR:` on stdout and exit 1: a broken convention-home pointer, a work-items.yaml
# the parser rejects, a non-string container_label (a mapping or a sequence), or a
# label holding a quote or control character (it is copied into single-quoted action
# arguments). Exit 2 for a usage error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RESOLVER="$PLUGIN_ROOT/lib/resolve-convention-home.sh"
PARSER="$PLUGIN_ROOT/skills/setup/scripts/yaml-subset.awk"
DEFAULT_LABEL="work-map"
DEFAULT_HOME="docs/conventions"
KEY="tracker.config.container_label"

error() {
  printf 'ERROR: %s\n' "$1"
  exit 1
}

root=""
while (($#)); do
  case "$1" in
  --root)
    (($# >= 2)) || { echo "container-label: --root needs a path" >&2; exit 2; }
    root="$2"
    shift
    ;;
  -h | --help)
    awk 'NR > 1 && /^set -uo/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "container-label: unknown argument: $1" >&2
    exit 2
    ;;
  esac
  shift
done

# The seam's root anchor: CLAUDE_PROJECT_DIR as set, else the git toplevel.
if [[ -z "$root" ]]; then
  root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
fi
if [[ -z "$root" || ! -d "$root" ]]; then
  printf '%s\n' "$DEFAULT_LABEL"
  exit 0
fi

home="$(bash "$RESOLVER" --root "$root" 2>/dev/null)"
case "$?" in
0) ;;
1) home="$DEFAULT_HOME" ;;
3) error "the convention-home pointer in $root is broken; run: bash \"$RESOLVER\" --root \"$root\" --explain" ;;
*)
  # A declined home, or a root no home applies to: no work-items.yaml binds it.
  printf '%s\n' "$DEFAULT_LABEL"
  exit 0
  ;;
esac

yaml="$root/$home/work-items.yaml"
if [[ ! -f "$yaml" ]]; then
  printf '%s\n' "$DEFAULT_LABEL"
  exit 0
fi

# The parser prints nothing for an empty flow sequence, so mark one in a value position
# as a scalar no YAML file can hold, as the seam's reader does, and reject it below.
EMPTY_SEQ=$'\002[]'
mark_empty_seqs() {
  LC_ALL=C awk -v marker="$EMPTY_SEQ" '
    BEGIN {
      key = "([A-Za-z0-9_-]+|\"([^\"\\\\]|\\\\.)*\"|\047([^\047]|\047\047)*\047)"
      lead = "^ *((- +)?" key "[ \t]*:[ \t]+|- +)"
    }
    {
      sub(/\r$/, "")
      if (NR == 1) sub(/^\357\273\277/, "")
      if (match($0, lead) && substr($0, RLENGTH + 1) ~ /^\[[ \t]*\][ \t]*(#.*)?$/)
        $0 = substr($0, 1, RLENGTH) "\"" marker "\""
      print
    }' "$1"
}

if ! records="$(mark_empty_seqs "$yaml" | LC_ALL=C awk -f "$PARSER")"; then
  error "$yaml does not parse: $(awk -F '\t' '$1 == "error" { print "line " $2 ": " $3 }' <<<"$records" | tail -n 1)"
fi

# A mapping or sequence under the key flattens to records below it; the seam rejects
# that shape rather than letting an unmatched label put maps on the frontier.
if awk -F '\t' -v key="$KEY." 'index($1, key) == 1 { found = 1 } END { exit !found }' <<<"$records"; then
  error "$KEY in $yaml must be a string"
fi

label="$(awk -F '\t' -v key="$KEY" '$1 == key { print substr($0, length($1) + 2); exit }' <<<"$records")"
[[ "$label" == "$EMPTY_SEQ" ]] && error "$KEY in $yaml must be a string"
label="${label:-$DEFAULT_LABEL}"

case "$label" in
*"'"* | *[[:cntrl:]]*) error "$KEY in $yaml holds a quote or control character" ;;
*) ;;
esac

printf '%s\n' "$label"
