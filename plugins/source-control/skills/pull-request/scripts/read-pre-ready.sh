#!/usr/bin/env bash
# Read which pre-flip steps `/source-control:pull-request ready` runs, from the
# `pre_ready` list in docs/conventions/source-control.yaml as the base branch
# holds it. Each item is a mapping `{step: <name>, enabled: true|false}`; a step
# the list does not name stays enabled. Parsing is lib/parse-concern-value.sh's.
#
# Usage:
#   read-pre-ready.sh -                    the file's text on stdin, fetched at the base
#   read-pre-ready.sh --ref <ref> <file>   the file as committed at <ref>
#                                          (a 40-hex commit id or origin/<name>)
#
# There is no working-tree form: the head branch must not choose its own gates.
#
# Output, tab-separated. First a source line:
#   source  default                 no pre_ready key, an empty list, or no file
#   source  config                  the list was read
#   source  fail-closed  <reason>   the list cannot be trusted: an unknown or
#                                   repeated step, a missing step or enabled, an
#                                   enabled other than true or false, a list item
#                                   that is not a mapping, a pre_ready that is not
#                                   a list, or a file the parser rejects
# Then one `<step>  enabled|disabled` line per step, in run order. Under
# default and fail-closed every step is enabled.
#
# Exit 0, or 2 for a usage error or a --ref that does not resolve (the caller
# then runs every step and reports the stderr line).
set -uo pipefail

STEPS=(base-merge plan-evidence code-review security-review verify)
PCV="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)/parse-concern-value.sh"

usage() {
  echo "read-pre-ready: usage: read-pre-ready.sh - | read-pre-ready.sh --ref <ref> <file>" >&2
  exit 2
}

src=() doc=""
case "${1:-}" in
-)
  (($# == 1)) || usage
  doc="$(cat)"
  ;;
--ref)
  (($# == 3)) || usage
  src=(--ref "$2" "$3")
  ;;
*) usage ;;
esac

# value <key>: one strict lookup; exit 3 when the parser rejects the document.
value() {
  if ((${#src[@]})); then
    bash "$PCV" --strict "${src[@]}" "$1"
  else
    bash "$PCV" --strict - "$1" <<<"$doc"
  fi
}

emit() {
  local source="$1" off="$2" step
  printf 'source\t%s\n' "$source"
  for step in "${STEPS[@]}"; do
    if [[ "$off" == *" $step "* ]]; then
      printf '%s\tdisabled\n' "$step"
    else
      printf '%s\tenabled\n' "$step"
    fi
  done
  exit 0
}

# The reason can quote the file's text, so control characters become spaces.
fail_closed() { emit "fail-closed"$'\t'"${1//[[:cntrl:]]/ }" " "; }

# lookup <var> <key>: set <var> to the value, failing closed on a parse error.
lookup() {
  local out rc
  out="$(value "$2")"
  rc=$?
  case $rc in
  0) printf -v "$1" '%s' "$out" ;;
  3) fail_closed "docs/conventions/source-control.yaml does not parse" ;;
  *) exit 2 ;;
  esac
}

lookup scalar pre_ready
[[ -z "$scalar" ]] || fail_closed "pre_ready is not a list"
for step in step enabled "${STEPS[@]}"; do
  lookup v "pre_ready.$step"
  lookup w "pre_ready.$step.enabled"
  [[ -z "$v$w" ]] || fail_closed "pre_ready is a mapping, not a list"
done

# A list holds at most one item per step, so an item past the last step is
# necessarily unknown or repeated and fails below.
off=" " seen=" " items=0
for ((i = 0; i <= ${#STEPS[@]}; i++)); do
  lookup step "pre_ready.$i.step"
  lookup enabled "pre_ready.$i.enabled"
  lookup item "pre_ready.$i"
  [[ -n "$step$enabled$item" ]] || break
  items=$((items + 1))
  [[ -z "$item" ]] || fail_closed "pre_ready item $i is not a {step, enabled} mapping"
  [[ -n "$step" ]] || fail_closed "pre_ready item $i has no step"
  [[ " ${STEPS[*]} " == *" $step "* ]] || fail_closed "unknown step '$step' in pre_ready"
  [[ "$seen" != *" $step "* ]] || fail_closed "step '$step' is listed twice in pre_ready"
  seen+="$step "
  case "$enabled" in
  true) ;;
  false) off+="$step " ;;
  '') fail_closed "step '$step' has no enabled value in pre_ready" ;;
  *) fail_closed "step '$step' has enabled '$enabled', not true or false" ;;
  esac
done

((items > 0)) || emit default " "
emit config "$off"
