#!/usr/bin/env bash
# Escape a scalar for a JSON string body, shared by the architecture collectors.
#
# Source this file. json_escape VALUE sets JSON_ESC to VALUE with backslash
# escaped first, then quote, then the tab, carriage return and newline JSON
# forbids raw: a Windows path is full of backslashes, so getting this order
# wrong corrupts every `path` field.
#
# Pure parameter expansion, and it assigns a global rather than printing,
# because BOTH an external process and a command substitution cost a fork. This
# runs once per emitted field, so the obvious `printf | awk` spelling inside
# `$(...)` measured near a second per field on a Windows checkout and dominated
# the whole collector.
#
# Executing this file prints usage and exits 2.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'json-escape.sh: source this file; it is not a command\n' >&2
  exit 2
fi

JSON_ESC=""
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  # shellcheck disable=SC2034 # read by the scripts that source this file
  JSON_ESC="$s"
}
