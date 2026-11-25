# shellcheck shell=bash

make_sink() {
  local s
  if [[ -z "${WORK:-}" || ! -d "$WORK" ]]; then
    echo "make_sink: \$WORK must be a directory the suite owns (got: ${WORK:-unset})" >&2
    return 2
  fi
  s="$(mktemp "$WORK/sink.XXXXXX")" || return 1
  printf '#!/usr/bin/env bash\n%s\n' "$1" >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}

wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

check_envelope() {
  local env_file="${1:-}" schema="${2:-${HOOK_ENVELOPE_SCHEMA:-}}" root reason rc
  if [[ -z "$schema" ]]; then
    root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)" || root=""
    schema="$root/docs/contracts/hook-telemetry/envelope.schema.json"
    [[ -s "$schema" ]] || schema="$root/docs/conventions/hook-telemetry/envelope.schema.json"
  fi
  if [[ ! -s "$schema" ]]; then
    echo "check_envelope: schema not found or empty: $schema" >&2
    return 1
  fi
  if [[ ! -f "$env_file" ]]; then
    echo "check_envelope: envelope file not found: ${env_file:-unset}" >&2
    return 1
  fi
  reason="$(jq -rn --slurpfile sc "$schema" --slurpfile ev "$env_file" '
    ($sc[0].required // []) as $req
    | ($sc[0].properties // {}) as $props
    | $ev[0] as $e
    | if ($sc | length) != 1 or ($req | type) != "array" or ($req | length) == 0
      then "schema has no required list"
      elif ($ev | length) != 1 or ($e | type) != "object"
      then "envelope is not one JSON object"
      else
        first(
          ($req[] | select(. as $k | $e | has($k) | not) | "missing required field " + .),
          ($props | to_entries[] | .key as $k | select($e | has($k))
            | .value as $p | $e[$k] as $v
            | ($v | type) as $vt
            | if ($p.type // null) == null then empty
              elif ($p.type == "integer" and ($vt != "number" or ($v | floor) != $v))
                or ($p.type != "integer" and $p.type != $vt)
              then "field " + $k + " is not " + $p.type
              elif ($p.minimum // null) != null and $vt == "number" and $v < $p.minimum
              then "field " + $k + " is below minimum " + ($p.minimum | tostring)
              else empty end)
        ) // empty
      end' 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "check_envelope: jq failed: ${reason%%$'\n'*}" >&2
    return 1
  fi
  if [[ -n "$reason" ]]; then
    echo "check_envelope: $reason" >&2
    return 1
  fi
}
