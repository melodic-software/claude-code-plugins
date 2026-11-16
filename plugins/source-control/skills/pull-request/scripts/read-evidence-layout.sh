# shellcheck shell=bash
# Resolve the two settings the evidence step reads: evidence_inline_max_captures, the most
# captures a change may have and still show them inline as a Before/After table, and
# evidence_record_fields, whether the comment carries the who, when and issues-found record.
#
# Resolution, lowest first: the default (4; false); the top-level key of
# docs/conventions/source-control.yaml as the pull request's base branch holds it. No userConfig
# level: both are repository policy. Parsing is lib/yaml-subset.awk's.
#
# Usage:
#   read-evidence-layout.sh
#       no repository level (no file read, or not a repository)
#   read-evidence-layout.sh --base <b> --default-branch <d> -
#       the file's text on stdin
#   read-evidence-layout.sh --base <b> --default-branch <d> --http-response
#       a `gh api -i` response on stdin: a 200 is read as the file, a 404 means no file
#
# The repository level counts only when --base matches --default-branch: any other base is a
# branch the PR's author may have pushed unreviewed. A base that does not match, a failed read, a
# file that does not parse, or input holding a NUL byte leaves the repository level unread, with a
# notice on stderr, and both keys take their defaults.
#
# A threshold other than a whole number from 0 to 999, or a switch other than true or false, is
# not used: that key takes its default, with a notice on stderr naming the level.
#
# Output, two tab-separated lines:
#   evidence_inline_max_captures  <n>             <level>
#   evidence_record_fields        <true|false>    <level>
# where <level> is `repository (docs/conventions/source-control.yaml at <base>)`, `default`, or
# `invalid value at <level> (fell back to <default>)`.
#
# Exit 0, or 2 for a usage error. It has no #! line and runs through bash, so it needs no
# executable bit.
set -uo pipefail

# shellcheck source=../../../lib/base-file.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)/base-file.sh"

usage() {
  echo "read-evidence-layout: usage: read-evidence-layout.sh [--base <b> --default-branch <d> (- | --http-response)]" >&2
  exit 2
}

notice() { printf 'read-evidence-layout: %s\n' "${1//[[:cntrl:]]/ }" >&2; }

mode="" base="" default="" has_base=0 has_default=0
while (($#)); do
  case "$1" in
  --base | --default-branch)
    (($# >= 2)) || usage
    if [[ "$1" == --base ]]; then base="$2" has_base=1; else default="$2" has_default=1; fi
    shift
    ;;
  - | --http-response)
    [[ -z "$mode" ]] || usage
    mode="$1"
    ;;
  *) usage ;;
  esac
  shift
done
if [[ -n "$mode" ]]; then
  ((has_base && has_default)) || usage
elif ((has_base || has_default)); then
  usage
fi

# Each key's value and level, defaults first.
max=4 max_level=default
rec=false rec_level=default

# pick <key> <value> <pattern> <default> <level>: print "<value>\t<level>" when value matches,
# else the default with an invalid-value level and a notice.
pick() {
  if [[ "$2" =~ $3 ]]; then
    printf '%s\t%s' "$2" "$5"
  else
    notice "$1 '$2' at $5 is not valid; using $4"
    printf '%s\tinvalid value at %s (fell back to %s)' "$4" "$5" "$4"
  fi
}

read_repo() {
  [[ -n "$base" ]] || { notice "the pull request's base branch could not be read; the repository level is unread"; return; }
  [[ -n "$default" ]] || { notice "the base repository's default branch could not be read; the repository level is unread"; return; }
  [[ "$base" == "$default" ]] || { notice "base $base is not the default branch $default; the repository level is unread"; return; }

  local level="repository (docs/conventions/source-control.yaml at $base)" k v picked
  base_file_load "$mode"
  [[ "$BASE_FILE_STATE" != absent ]] || return
  if [[ "$BASE_FILE_STATE" == failed ]] || ! base_file_records; then
    notice "$BASE_FILE_REASON; the repository level is unread"
    return
  fi
  # A key nested under one of the two (a list or a mapping) is not a single value.
  local -A seen=()
  while IFS=$'\t' read -r k v; do
    case "$k" in
    evidence_inline_max_captures | evidence_record_fields) seen[$k]="$v" ;;
    evidence_inline_max_captures.* | evidence_record_fields.*) seen[${k%%.*}]="(not a single value)" ;;
    *) ;;
    esac
  done <<<"$BASE_FILE_RECORDS"
  if [[ -v 'seen[evidence_inline_max_captures]' ]]; then
    picked="$(pick evidence_inline_max_captures "${seen[evidence_inline_max_captures]}" '^(0|[1-9][0-9]{0,2})$' 4 "$level")"
    max="${picked%%$'\t'*}" max_level="${picked#*$'\t'}"
  fi
  if [[ -v 'seen[evidence_record_fields]' ]]; then
    picked="$(pick evidence_record_fields "${seen[evidence_record_fields]}" '^(true|false)$' false "$level")"
    rec="${picked%%$'\t'*}" rec_level="${picked#*$'\t'}"
  fi
}

[[ -z "$mode" ]] || read_repo

printf 'evidence_inline_max_captures\t%s\t%s\n' "$max" "$max_level"
printf 'evidence_record_fields\t%s\t%s\n' "$rec" "$rec_level"
