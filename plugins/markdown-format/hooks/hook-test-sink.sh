# shellcheck shell=bash
# Telemetry-sink stub for hook test suites. Sourced, never executed: sourcing
# defines make_sink, wait_for_sink and check_envelope and runs nothing else.
#
# CONTRACT. hook::emit_telemetry runs HOOK_TELEMETRY_SINK as one quoted word,
# "$sink", with the envelope on stdin. The value must therefore be a single
# executable path, never a command with arguments: `tee FILE` (or
# `/usr/bin/tee FILE`) is looked up as one file name, is not found, and
# delivers nothing without an error. A suite points HOOK_TELEMETRY_SINK at the
# stub make_sink writes.
#
# The sink runs fire-and-forget in a background subshell, so an assertion on
# what it captured has to wait for it. wait_for_sink is that wait, bounded so a
# sink that never fires fails the assertion instead of hanging the suite.
#
# check_envelope asserts a captured envelope against
# docs/conventions/hook-telemetry/envelope.schema.json, reading the required
# fields, their types and their minimums from that file with jq, so a suite
# carries no transcribed field list to drift from the schema.
#
# make_sink requires $WORK: a directory the suite owns and removes on exit.
#
# Canonical copy: lib/hook-test-sink.sh at the marketplace repo root. Plugins
# carry byte-identical copies at plugins/<plugin>/hooks/hook-test-sink.sh
# because an installed plugin is cache-isolated; edit the canonical file and
# copy it over the plugin copies.

# make_sink <body> -> print the path of an executable stub sink: a bash shebang
# line followed by <body>, which reads the envelope on stdin. Returns 2 with a
# message on stderr when $WORK is not a directory, so a suite cannot write
# stubs somewhere it never cleans up.
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

# wait_for_sink <file> [tries=150] -> block until <file> is non-empty (the sink
# has flushed) and return 0, or return 1 after <tries> polls of 20ms each. The
# poll replaces a fixed sleep, which races the spawn latency of the sink.
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

# check_envelope <envelope-file> [schema-file] -> return 0 when the envelope
# conforms to the schema, else return 1 with a one-line reason on stderr. Checks
# that the file holds one JSON object, that every `.required` key is present,
# that each present `.properties` entry matches its declared `type` ("integer"
# means a number with no fraction), and that `minimum` holds. The schema is
# [schema-file], else $HOOK_ENVELOPE_SCHEMA, else the repo's envelope.schema.json
# found through git from this file. A missing schema or an empty `.required`
# fails: the check never passes for want of a field list.
check_envelope() {
  local env_file="${1:-}" schema="${2:-${HOOK_ENVELOPE_SCHEMA:-}}" root reason rc
  if [[ -z "$schema" ]]; then
    root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)" || root=""
    schema="$root/docs/conventions/hook-telemetry/envelope.schema.json"
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
          ($props | to_entries[] | select(.key as $k | $e | has($k))
            | .key as $k | .value as $p | $e[$k] as $v
            | ($v | type) as $vt
            | if ($p.type // null) == null then empty
              elif ($p.type == "integer" and ($vt != "number" or ($v | floor) != $v))
                or ($p.type != "integer" and $p.type != $vt)
              then "field " + $k + " is not " + $p.type
              elif ($p.minimum // null) != null and $vt == "number" and $v < $p.minimum
              then "field " + $k + " is below minimum " + ($p.minimum | tostring)
              else empty end),
          empty
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
