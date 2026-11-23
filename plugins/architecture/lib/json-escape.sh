#!/usr/bin/env bash

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
