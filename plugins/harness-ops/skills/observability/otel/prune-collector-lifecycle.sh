#!/usr/bin/env bash
case "${OSTYPE:-}" in
msys* | cygwin* | win*) OS_KIND=windows ;;
*) OS_KIND=unsupported ;;
esac
readonly OS_KIND
readonly COLLECTOR_SERVICE_NAME='otelcol-contrib'
readonly POLL_INTERVAL_SECONDS=0.25
readonly POLL_MAX_TRIES=40
readonly SENTINEL_MAX_AGE_MINUTES="${CC_OTEL_SENTINEL_MAX_AGE_MINUTES:-60}"

OWNER_ID=""
OWN_SENTINEL=false
STAMP_DIR=""
STOPPED=false
SENTINEL=""

take_sentinel() {
  [[ -n "$OWNER_ID" ]] || OWNER_ID="$$ $(proc_start "$$")"
  mkdir "$SENTINEL" 2>/dev/null && (set -o noclobber && printf '%s\n' "$OWNER_ID" >"$SENTINEL/owner") 2>/dev/null
}
release_sentinel() {
  rm -f "$SENTINEL/owner" 2>/dev/null || true
  rmdir "$SENTINEL" 2>/dev/null || true
}

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

service_ps() {
  require_windows_service || return 1
  powershell.exe -NoProfile -NonInteractive -Command "\$ErrorActionPreference='Stop'; $1" >/dev/null
}

default_stop() { service_ps "Stop-Service -Name '$COLLECTOR_SERVICE_NAME' -ErrorAction Stop"; }
default_start() { service_ps "Start-Service -Name '$COLLECTOR_SERVICE_NAME' -ErrorAction Stop"; }
default_running() {
  service_ps "try { if ((Get-Service -Name '$COLLECTOR_SERVICE_NAME' -ErrorAction Stop).Status -eq 'Stopped') { exit 1 }; exit 0 } catch { Write-Error \$_; exit 2 }"
}

stop_collector() {
  if [[ -n "${CC_OTEL_STOP_CMD:-}" ]]; then
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

wait_collector_gone() {
  local tries=0 rc
  while true; do
    rc=0
    collector_running || rc=$?
    case "$rc" in
      0) ;;
      1) return 0 ;;
      *) return 2 ;;
    esac
    tries=$((tries + 1))
    ((tries < POLL_MAX_TRIES)) || return 1
    sleep "$POLL_INTERVAL_SECONDS"
  done
}

manages_collector() { [[ "$OS_KIND" == windows || -n "${CC_OTEL_RUNNING_CMD:-}" ]]; }

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

ensure_collector_briefly() {
  manages_collector || return 0
  local rc=0
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
  if [[ "$STOPPED" == true ]]; then
    if ! start_collector; then
      err "failed to restart Collector service '$COLLECTOR_SERVICE_NAME'"
      if ((original_rc == 0)); then original_rc=1; fi
    fi
  fi
  if ((original_rc == 0)) && [[ -n "$STAMP_DIR" ]]; then stamp_last_prune "$STAMP_DIR"; fi
  if [[ "$OWN_SENTINEL" == true && -n "$SENTINEL" && -d "$SENTINEL" ]]; then
    release_sentinel
  fi
  trap - EXIT
  exit "$original_rc"
}
