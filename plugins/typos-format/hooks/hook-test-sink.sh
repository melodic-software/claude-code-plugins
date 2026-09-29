# shellcheck shell=bash
# Telemetry-sink stub for hook test suites. Sourced, never executed: sourcing
# defines make_sink and wait_for_sink and runs nothing else.
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
# Requires $WORK: a directory the suite owns and removes on exit.
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
