#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'redact-connection.sh: source this file; it is not a command\n' >&2
  exit 2
fi

_REDACT_CONNECTION_AWK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/redact-connection.awk"

redact_connection_shape() {
  local key="$1" value="$2" out
  out="$(
    REDACT_KEY="$key" REDACT_VALUE="$value" awk -f "$_REDACT_CONNECTION_AWK" -f - <<'AWK'
BEGIN {
  redact_begin()
  redact_shape(ENVIRON["REDACT_KEY"], ENVIRON["REDACT_VALUE"])
  redact_dump("")
}
AWK
  )"
  [[ -n "$out" ]] || return 1
  printf '%s\n' "$out" | awk -F'\t' '
    NF >= 3 {
      printf "%s\t%s\t%s", $1, $2, $3
      if ($5 != "" || $6 != "") printf "\t%s\t%s", $5, $6
      printf "\n"
    }'
}

redact_is_secret() {
  REDACT_KEY="$1" REDACT_VALUE="$2" awk -f "$_REDACT_CONNECTION_AWK" -f - <<'AWK'
BEGIN { exit !redact_secret(ENVIRON["REDACT_KEY"], ENVIRON["REDACT_VALUE"]) }
AWK
}
