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
# A prune stops the Collector for seconds to a few minutes; a lock older than this is a problem.
# CC_OTEL_SENTINEL_MAX_AGE_MINUTES overrides it; prune-otel-store.sh validates it.
readonly SENTINEL_MAX_AGE_MINUTES="${CC_OTEL_SENTINEL_MAX_AGE_MINUTES:-60}"

OWNER_ID=""
# Trap state (script-level so the EXIT trap sees them).
OWN_SENTINEL=false
STAMP_DIR=""
STOPPED=false
SENTINEL=""

# Take the sentinel, or return 1 when another prune holds it. It stays a directory, which the
# Collector start script tests for (-d), but the directory alone is not an arbiter everywhere:
# uutils mkdir (Ubuntu 25.10+) lets two racers both succeed. An owner token created with
# noclobber (bash's own O_EXCL open, atomic on GNU, uutils, macOS and Git Bash) decides.
#   Claim: two racing uutils `mkdir` calls on one path can both succeed; a noclobber `>` cannot.
#   Basis: measured with `mkdir (uutils coreutils) 0.10.0` on Ubuntu 26.04 (both won 62 of 200
#     races; GNU mkdir 0 of 200); bash's redir.c `noclobber_open` creates with O_EXCL.
#   As of: 2026-09-28.
#   Recheck: a uutils release that makes mkdir fail on an existing directory under a race.
take_sentinel() {
  [[ -n "$OWNER_ID" ]] || OWNER_ID="$$ $(proc_start "$$")"
  mkdir "$SENTINEL" 2>/dev/null && (set -o noclobber && printf '%s\n' "$OWNER_ID" >"$SENTINEL/owner") 2>/dev/null
}
release_sentinel() {
  rm -f "$SENTINEL/owner" 2>/dev/null || true
  rmdir "$SENTINEL" 2>/dev/null || true
}

# Print a process's start time, or nothing when it is gone. The owner token holds "<pid> <start>",
# so a reused pid does not pass for the holder. /proc covers Linux and Git Bash; macOS has no /proc.
proc_start() {
  local stat
  local -a fields
  if [[ -d /proc/self ]]; then
    { read -r stat <"/proc/$1/stat"; } 2>/dev/null || return 0
    read -ra fields <<<"${stat##*) }"
    printf '%s\n' "${fields[19]:-}" # field 22, starttime
  else
    ps -o lstart= -p "$1" 2>/dev/null || true
  fi
}

# Judge the sentinel's holder: 0 = stale (holder gone, or no owner token and older than
# SENTINEL_MAX_AGE_MINUTES), 1 = live or young, 3 = a live holder past the bound.
sentinel_state() {
  local owner="" pid start old
  { read -r owner <"$SENTINEL/owner"; } 2>/dev/null || true
  read -r pid start <<<"$owner" || true
  old="$(find "$SENTINEL" -maxdepth 0 -mmin "+$SENTINEL_MAX_AGE_MINUTES" 2>/dev/null)"
  if [[ -n "${pid:-}" && -n "${start:-}" ]]; then
    [[ "$(proc_start "$pid")" == "$start" ]] || return 0
    [[ -n "$old" ]] && return 3
    return 1
  fi
  [[ -n "$old" ]] || return 1
}

# Take the sentinel, recovering a stale one; returns 1 or 3 (see sentinel_state) when it is held.
# Recovery runs under a second token, so every recoverer judges the sentinel only after the last
# one finished: a run that read the dead owner cannot then remove the lock a peer just took.
# The guard is held for milliseconds, so one older than a minute is from a killed run.
acquire_sentinel() {
  take_sentinel && return 0
  local guard="$SENTINEL.takeover" owner="" rc=0
  if [[ -n "$(find "$guard" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then rm -rf "${guard:?}"; fi
  mkdir "$guard" 2>/dev/null || true
  (set -o noclobber && : >"$guard/owner") 2>/dev/null || return 1
  if [[ -e "$SENTINEL" ]]; then
    sentinel_state || rc=$?
    if ((rc == 0)); then
      { read -r owner <"$SENTINEL/owner"; } 2>/dev/null || true
      rm -rf "${SENTINEL:?}"
      err "took over a stale sentinel ($SENTINEL, owner: ${owner:-none}): its prune is gone"
    fi
  fi
  ((rc != 0)) || take_sentinel || rc=1
  rm -f "$guard/owner"
  rmdir "$guard" 2>/dev/null || true
  return "$rc"
}

lock_held_too_long() {
  err "a live prune has held $SENTINEL for over $SENTINEL_MAX_AGE_MINUTES minutes"
}

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

# The service exists only on Windows; a set query seam stands in for it in tests.
manages_collector() { [[ "$OS_KIND" == windows || -n "${CC_OTEL_RUNNING_CMD:-}" ]]; }

# Start the Collector when it is Stopped; the caller holds the sentinel. Returns 1 only when the
# start fails. A failed query is reported and left alone.
ensure_collector_running() {
  manages_collector || return 0
  local rc=0
  collector_running || rc=$?
  if ((rc == 2)); then err "failed to query Collector service status"; fi
  ((rc == 1)) || return 0
  err "Collector service '$COLLECTOR_SERVICE_NAME' is stopped and no prune holds the lock — starting it"
  start_collector && return 0
  err "failed to start Collector service '$COLLECTOR_SERVICE_NAME'"
  return 1
}

# Restore a Collector a killed prune left stopped, on the paths that do not stop it themselves.
# Quiet while a live prune holds the lock; returns 1 when that lock outlasts the bound.
ensure_collector_briefly() {
  manages_collector || return 0
  local rc=0
  # No store directory, so no prune can hold a lock in it.
  if [[ ! -d "${SENTINEL%/*}" ]]; then
    ensure_collector_running || rc=$?
    return "$rc"
  fi
  acquire_sentinel || rc=$?
  if ((rc == 3)); then lock_held_too_long; fi
  ((rc == 0)) || return $((rc == 3))
  ensure_collector_running || rc=$?
  release_sentinel
  return "$rc"
}

cleanup() {
  local original_rc=$?
  # Restart only if this prune stopped it. A restart failure must be visible: silently leaving
  # the machine telemetry service down is worse than converting an otherwise successful prune
  # into a failure. Keep the sentinel through this attempt so another prune cannot start while
  # the Collector is still down or restarting.
  if [[ "$STOPPED" == true ]]; then
    if ! start_collector; then
      err "failed to restart Collector service '$COLLECTOR_SERVICE_NAME'"
      if ((original_rc == 0)); then original_rc=1; fi
    fi
  fi
  # The probe reads the stamp as proof of a completed run, so write it only after a clean restart.
  if ((original_rc == 0)) && [[ -n "$STAMP_DIR" ]]; then stamp_last_prune "$STAMP_DIR"; fi
  # Release last: the sentinel covers the complete stop -> mutate -> restart lifecycle, including
  # a failed restart attempt. The next operator run may then retry recovery explicitly.
  if [[ "$OWN_SENTINEL" == true && -n "$SENTINEL" && -d "$SENTINEL" ]]; then
    release_sentinel
  fi
  trap - EXIT
  exit "$original_rc"
}
