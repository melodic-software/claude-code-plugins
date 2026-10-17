#!/usr/bin/env bash
# Read which pre-flip steps `/source-control:pull-request ready` runs, from the
# `pre_ready` list in docs/conventions/source-control.yaml as the base branch
# holds it. Each item is a mapping `{step: <name>, enabled: true|false}`; a step
# the list does not name stays enabled. Parsing is lib/yaml-subset.awk's, the
# shared YAML-subset parser; the reader is at least as strict as
# schemas/source-control.schema.json.
#
# Usage:
#   read-pre-ready.sh --base <b> --default-branch <d> -
#       the file's text on stdin
#   read-pre-ready.sh --base <b> --default-branch <d> --http-response
#       a `gh api -i` response on stdin: a 200 is read as the file, a 404
#       means no file, anything else fails closed
#
# --base is the pull request's base branch and --default-branch the base
# repository's default branch. The list is honored only when the two match:
# any other base is a branch the PR's author may have pushed unreviewed. An
# empty value or a mismatch fails closed. There is no file-path form: the head
# branch must not choose its own gates, so the caller fetches the base's copy.
#
# Output, tab-separated. First a source line:
#   source  default                 no file, no pre_ready key, or an empty list
#   source  config                  the list was read
#   source  fail-closed  <reason>   the list cannot be trusted: the base is
#                                   not the default branch, the base read
#                                   failed, the input holds a NUL byte, the
#                                   file does not parse, pre_ready
#                                   repeats or is not a list, an item is not a
#                                   {step, enabled} mapping or holds another
#                                   key, a step is missing, unknown or repeated,
#                                   or enabled is missing, quoted, or not true
#                                   or false
# Then one `<step>  enabled|disabled` line per step, in run order. Under
# default and fail-closed every step is enabled.
#
# Exit 0, or 2 for a usage error.
set -uo pipefail

# shellcheck source=pre-ready-steps.sh
source "$(dirname "${BASH_SOURCE[0]}")/pre-ready-steps.sh"
STEPS=("${PRE_READY_STEPS[@]}")
PARSER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)/yaml-subset.awk"

usage() {
  echo "read-pre-ready: usage: read-pre-ready.sh --base <b> --default-branch <d> (- | --http-response)" >&2
  exit 2
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

# The reason can quote the file or the response, so control characters become spaces.
fail_closed() { emit "fail-closed"$'\t'"${1//[[:cntrl:]]/ }" " "; }

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
((has_base && has_default)) && [[ -n "$mode" ]] || usage

[[ -n "$base" ]] || fail_closed "the pull request's base branch could not be read"
[[ -n "$default" ]] || fail_closed "the base repository's default branch could not be read"
[[ "$base" == "$default" ]] || fail_closed "base $base is not the default branch $default"

# A command substitution drops NUL bytes (`fal\0se` would read as `false`), so
# stdin goes to a file and is checked before any variable holds it.
input_file="$(mktemp)" || fail_closed "no temporary file for the input"
trap 'rm -f "$input_file"' EXIT
cat >"$input_file"
(($(tr -d '\000' <"$input_file" | wc -c) == $(wc -c <"$input_file"))) ||
  fail_closed "the input holds a NUL byte"

case "$mode" in
-) doc="$(cat "$input_file")" ;;
--http-response)
  response="$(cat "$input_file")"
  [[ -n "$response" ]] || fail_closed "the base read returned no response"
  status="${response%%$'\n'*}"
  status="${status%$'\r'}"
  [[ "$status" =~ ^HTTP/[0-9.]+\ ([0-9]{3}) ]] || fail_closed "the base read returned no status line"
  case "${BASH_REMATCH[1]}" in
  200) doc="$(awk 'body { print; next } { sub(/\r$/, "") } $0 == "" { body = 1 }' <<<"$response")" ;;
  404) emit default " " ;;
  *) fail_closed "the base read returned $status" ;;
  esac
  ;;
*) usage ;;
esac

# The parser's records drop quoting, and an empty first pre_ready leaves no
# record of itself, so a repeated top-level key and a quoted enabled are found
# in the text.
q="[\"']?"
(($(grep -cE "^[[:space:]]*${q}pre_ready${q}[[:space:]]*:" <<<"$doc") <= 1)) ||
  fail_closed "pre_ready appears more than once"

records="$(LC_ALL=C awk -f "$PARSER" <<<"$doc")" ||
  fail_closed "docs/conventions/source-control.yaml does not parse"

seen=$'\n' max=-1
while IFS=$'\t' read -r key val; do
  case "$key" in pre_ready | pre_ready.*) ;; *) continue ;; esac
  [[ "$key" != pre_ready ]] || fail_closed "pre_ready is not a list"
  rest="${key#pre_ready.}"
  idx="${rest%%.*}"
  [[ "$idx" =~ ^[0-9]+$ ]] || fail_closed "pre_ready is a mapping, not a list"
  [[ "$rest" != "$idx" ]] || fail_closed "pre_ready item $idx is not a {step, enabled} mapping"
  sub="${rest#"$idx".}"
  top="${sub%%.*}"
  [[ ! "$top" =~ ^[0-9]+$ ]] || fail_closed "pre_ready item $idx is not a {step, enabled} mapping"
  if [[ "$sub" != step && "$sub" != enabled ]]; then
    [[ "$top" != step && "$top" != enabled ]] || fail_closed "pre_ready item $idx's $top is not a single value"
    fail_closed "pre_ready item $idx has an unknown key '$top'"
  fi
  [[ "$seen" != *$'\n'"$key"$'\n'* ]] || fail_closed "pre_ready item $idx repeats a key"
  seen+="$key"$'\n'
  printf -v "item_${idx}_$sub" '%s' "$val"
  ((idx <= max)) || max=$idx
done <<<"$records"

((max >= 0)) || emit default " "

grep -qE "(^|[[:space:]{,-])${q}enabled${q}[[:space:]]*:[[:space:]]*[\"']" <<<"$doc" &&
  fail_closed "an enabled value in pre_ready is quoted, not a boolean"

off=" " steps_seen=" "
for ((i = 0; i <= max; i++)); do
  step_var="item_${i}_step" enabled_var="item_${i}_enabled"
  step="${!step_var:-}" enabled="${!enabled_var:-}"
  [[ -n "$step" ]] || fail_closed "pre_ready item $i has no step"
  [[ " ${STEPS[*]} " == *" $step "* ]] || fail_closed "unknown step '$step' in pre_ready"
  [[ "$steps_seen" != *" $step "* ]] || fail_closed "step '$step' is listed twice in pre_ready"
  steps_seen+="$step "
  case "$enabled" in
  true) ;;
  false) off+="$step " ;;
  '') fail_closed "step '$step' has no enabled value in pre_ready" ;;
  *) fail_closed "step '$step' has enabled '$enabled', not true or false" ;;
  esac
done

emit config "$off"
