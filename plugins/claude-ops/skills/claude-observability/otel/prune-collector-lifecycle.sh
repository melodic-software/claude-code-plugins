#!/usr/bin/env bash
# prune-collector-lifecycle.sh — Collector stop/start and prune sentinel locking.
# Sourced by prune-otel-store.sh; not an entry point.
#
# Requires SCRIPT_DIR and err() from the caller.

case "${OSTYPE:-}" in
  msys* | cygwin* | win*) OS_KIND=windows ;;
  *) OS_KIND=posix ;;
esac
readonly OS_KIND

readonly POLL_INTERVAL_SECONDS=0.25
readonly POLL_MAX_TRIES=40 # 40 * 0.25s = 10s for the Collector to release its file handle

# Trap state (script-level so the EXIT trap sees them).
OWN_SENTINEL=false
STOPPED=false
SENTINEL=""
START_SCRIPT=""

# Platform stop / running-check. Overridable via CC_OTEL_STOP_CMD / CC_OTEL_RUNNING_CMD (test seams).
default_stop() {
  if [[ "$OS_KIND" == windows ]]; then
    MSYS_NO_PATHCONV=1 taskkill /F /IM otelcol-contrib.exe >/dev/null 2>&1 || true
  else
    pkill -f otelcol-contrib >/dev/null 2>&1 || true
  fi
}

default_running() {
  if [[ "$OS_KIND" == windows ]]; then
    MSYS_NO_PATHCONV=1 tasklist /FI "IMAGENAME eq otelcol-contrib.exe" 2>/dev/null | grep -qi otelcol-contrib
  else
    pgrep -f otelcol-contrib >/dev/null 2>&1
  fi
}

stop_collector() {
  if [[ -n "${CC_OTEL_STOP_CMD:-}" ]]; then
    "$CC_OTEL_STOP_CMD"
    return
  fi
  default_stop
}

collector_running() {
  if [[ -n "${CC_OTEL_RUNNING_CMD:-}" ]]; then
    "$CC_OTEL_RUNNING_CMD"
    return
  fi
  default_running
}

# Poll until the Collector process is gone. Returns 1 if still running after POLL_MAX_TRIES.
wait_collector_gone() {
  local tries=0
  while collector_running; do
    ((tries += 1)) || true
    if ((tries >= POLL_MAX_TRIES)); then return 1; fi
    sleep "$POLL_INTERVAL_SECONDS"
  done
  return 0
}

cleanup() {
  if [[ "$OWN_SENTINEL" == true && -n "$SENTINEL" && -d "$SENTINEL" ]]; then
    rmdir "$SENTINEL" 2>/dev/null || true
  fi
  # Restart only if we stopped it — leaves the Collector running on every exit path, including
  # an error mid-trim. Idempotent: start-collector.sh no-ops if :4318 is already bound.
  if [[ "$STOPPED" == true && -n "$START_SCRIPT" ]]; then
    bash "$START_SCRIPT" >/dev/null 2>&1 || true
  fi
}
