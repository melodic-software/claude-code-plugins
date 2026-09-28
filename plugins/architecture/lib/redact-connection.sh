#!/usr/bin/env bash
# Connection-shape redaction shared by map-deployment and, when they land,
# map-context and map-containers.
#
# Source this file. redact_connection_shape KEY VALUE prints zero or more
# lines of "kind<TAB>host<TAB>port" and returns 0 when it printed a line, 1
# when the value yielded no external shape. The raw value is never printed.
#
# Executing this file prints usage and exits 2. The awk implementation is
# redact-connection.awk beside this file.

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
  printf '%s\n' "$out" | awk -F'\t' 'NF >= 3 { printf "%s\t%s\t%s\n", $1, $2, $3 }'
}
