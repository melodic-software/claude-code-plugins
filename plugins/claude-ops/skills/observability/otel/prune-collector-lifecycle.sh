#!/usr/bin/env bash
# prune-collector-lifecycle.sh — Windows Collector service lifecycle + prune locking.
# Sourced by prune-otel-store.sh; not an entry point.
#
# Requires err() from the caller. The production path controls only the provisioning-owned
# otelcol-contrib Windows service. Command overrides are hermetic test seams.

case "${OSTYPE:-}" in
  msys* | cygwin* | win*) OS_KIND=windows ;;
  *) OS_KIND=unsupported ;;
esac
readonly OS_KIND
readonly COLLECTOR_SERVICE_NAME='otelcol-contrib'
readonly POLL_INTERVAL_SECONDS=0.25
readonly POLL_MAX_TRIES=40 # 40 * 0.25s = 10s

# Trap state (script-level so the EXIT trap sees them).
OWN_SENTINEL=false
STOPPED=false
SENTINEL=""

require_windows_service() {
  if [[ "$OS_KIND" != windows ]]; then
    err "Collector retention lifecycle requires the provisioning-owned Windows service '$COLLECTOR_SERVICE_NAME'"
    return 1
  fi
}

default_stop() {
  require_windows_service || return 1
  powershell.exe -NoProfile -NonInteractive -Command \
    "\$ErrorActionPreference='Stop'; Stop-Service -Name '$COLLECTOR_SERVICE_NAME' -ErrorAction Stop" \
    >/dev/null
}

default_start() {
  require_windows_service || return 1
  powershell.exe -NoProfile -NonInteractive -Command \
    "\$ErrorActionPreference='Stop'; Start-Service -Name '$COLLECTOR_SERVICE_NAME' -ErrorAction Stop" \
    >/dev/null
}

default_running() {
  require_windows_service || return 1
  powershell.exe -NoProfile -NonInteractive -Command \
    "\$ErrorActionPreference='Stop'; try { if ((Get-Service -Name '$COLLECTOR_SERVICE_NAME' -ErrorAction Stop).Status -eq 'Stopped') { exit 1 }; exit 0 } catch { Write-Error \$_; exit 2 }" \
    >/dev/null
}

stop_collector() {
  if [[ -n "${CC_OTEL_STOP_CMD:-}" ]]; then
    # Capture explicitly rather than a bare `return` after the command: under `set -e`,
    # a caller-side conditional (this is invoked from `if !`/`while` sites) suppresses
    # errexit for the whole dynamic scope, and bash's propagation of the suppressed
    # command's $? through an implicit `return` differs across bash versions (observed:
    # lost on bash 5.2, preserved on 5.3). `|| rc=$?` + explicit `return "$rc"` is
    # version-independent.
    local rc=0
    "$CC_OTEL_STOP_CMD" || rc=$?
    return "$rc"
  fi
  default_stop
}

start_collector() {
  if [[ -n "${CC_OTEL_START_CMD:-}" ]]; then
    local rc=0
    "$CC_OTEL_START_CMD" || rc=$?
    return "$rc"
  fi
  default_start
}

collector_running() {
  if [[ -n "${CC_OTEL_RUNNING_CMD:-}" ]]; then
    local rc=0
    "$CC_OTEL_RUNNING_CMD" || rc=$?
    return "$rc"
  fi
  default_running
}

# Poll until the service reaches Stopped. Returns 1 if still running after POLL_MAX_TRIES and
# 2 when service state cannot be queried. A query error is not evidence that the service stopped.
wait_collector_gone() {
  local tries=0 query_rc
  while true; do
    if collector_running; then
      ((tries += 1)) || true
      if ((tries >= POLL_MAX_TRIES)); then return 1; fi
      sleep "$POLL_INTERVAL_SECONDS"
      continue
    else
      query_rc=$?
    fi
    if ((query_rc == 1)); then return 0; fi
    return 2
  done
}

cleanup() {
  local original_rc=$?
  # Restart only if this prune stopped it. A restart failure must be visible: silently leaving
  # the machine telemetry service down is worse than converting an otherwise successful prune
  # into a failure. Keep the sentinel through this attempt so another prune cannot start while
  # the Collector is still down or restarting.
  if [[ "$STOPPED" == true ]]; then
    if start_collector; then
      :
    else
      err "failed to restart Collector service '$COLLECTOR_SERVICE_NAME'"
      if ((original_rc == 0)); then original_rc=1; fi
    fi
  fi
  # Release last: the sentinel covers the complete stop -> mutate -> restart lifecycle, including
  # a failed restart attempt. The next operator run may then retry recovery explicitly.
  if [[ "$OWN_SENTINEL" == true && -n "$SENTINEL" && -d "$SENTINEL" ]]; then
    rmdir "$SENTINEL" 2>/dev/null || true
  fi
  trap - EXIT
  exit "$original_rc"
}
