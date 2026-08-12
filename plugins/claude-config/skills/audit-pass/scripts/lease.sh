#!/usr/bin/env bash
# lease.sh — run lease for audit-pass (acquire / heartbeat / release / classify).
#
# Implements the lease contract in reference/run-state-and-resumability.md §3:
# JSON lease at runs/<state-key>/<run-id>/lease with run_id, pid, started_at,
# heartbeat_at, owner_epoch, and an optional released tombstone.
#
# Usage:
#   lease.sh acquire  --lease-path <file> --run-id <id>
#   lease.sh heartbeat --lease-path <file> --run-id <id> --owner-epoch <n>
#   lease.sh release  --lease-path <file> --run-id <id>
#   lease.sh classify --lease-path <file>
#   lease.sh adopt    --lease-path <file> --run-id <id> --expected-epoch <n>
#
# classify prints: released | live | stale | missing
# Exit codes: 0 success; 1 usage/error; 2 live lease blocks attach; 3 stale/missing for adopt

set -euo pipefail

HEARTBEAT_LIVE_SECONDS=300   # 5 minutes — five 60s refresh intervals
HEARTBEAT_FUTURE_SLOP=60     # heartbeat_at must not be >60s in the future

usage() {
  cat <<'EOF'
lease.sh — audit-pass run lease (see reference/run-state-and-resumability.md)

Subcommands:
  acquire   create a new lease, or refuse when a live lease is held
  heartbeat refresh heartbeat_at for the holder's owner_epoch
  release   write a released tombstone for this run id
  classify  print released | live | stale | missing
  adopt     compare-and-set adopt a stale lease (increments owner_epoch)

Common flags:
  --lease-path <file>   absolute path to the lease JSON file
  --run-id <id>         run identifier (acquire/heartbeat/release/adopt)
  --owner-epoch <n>     epoch the holder owns (heartbeat)
  --expected-epoch <n>  observed epoch to adopt from (adopt)
EOF
}

iso_utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

epoch_seconds() {
  local ts="$1" out
  # portability-ok: GNU date -d with BSD date -j fallback; dual-path epoch parsing per #1709
  if out=$(date -u -d "$ts" +%s 2>/dev/null); then
    printf '%s\n' "$out"
  else
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s
  fi
}

lease_classify_state() {
  # lease_classify_state <lease-path> — prints released|live|stale|missing
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'missing\n'
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq required" >&2
    return 1
  fi
  if ! tr -d '\r' <"$path" | jq -e . >/dev/null 2>&1; then
    printf 'stale\n'
    return 0
  fi
  local state
  state="$(tr -d '\r' <"$path" | jq -r '.state // "active"')"
  if [[ "$state" == "released" ]]; then
    printf 'released\n'
    return 0
  fi
  local hb now hb_s now_s delta
  hb="$(tr -d '\r' <"$path" | jq -r '.heartbeat_at // empty')"
  [[ -n "$hb" ]] || { printf 'stale\n'; return 0; }
  now="$(iso_utc_now)"
  hb_s="$(epoch_seconds "$hb")"
  now_s="$(epoch_seconds "$now")"
  delta=$((now_s - hb_s))
  if (( delta < -HEARTBEAT_FUTURE_SLOP || delta >= HEARTBEAT_LIVE_SECONDS )); then
    printf 'stale\n'
  else
    printf 'live\n'
  fi
}

write_lease_atomic() {
  # write_lease_atomic <lease-path> <json-object>
  local path="$1" json="$2" dir tmp
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.lease.XXXXXX")"
  printf '%s\n' "$json" >"$tmp"
  mv -f "$tmp" "$path"
}

cmd_acquire() {
  local path="" run_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lease-path) path="$2"; shift 2 ;;
      --run-id) run_id="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  [[ -n "$path" && -n "$run_id" ]] || { usage >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; return 1; }

  local class
  class="$(lease_classify_state "$path")"
  case "$class" in
    live)
      local holder hb
      holder="$(tr -d '\r' <"$path" | jq -r '.run_id // "unknown"')"
      hb="$(tr -d '\r' <"$path" | jq -r '.heartbeat_at // "unknown"')"
      echo "ERROR: live lease held by run_id=$holder heartbeat_at=$hb" >&2
      return 2
      ;;
    released)
      echo "ERROR: lease is released — adopt or choose a new run id/path" >&2
      return 1
      ;;
    stale | missing) ;;
    *)
      echo "ERROR: unexpected lease state: $class" >&2
      return 1
      ;;
  esac

  local now epoch=1
  now="$(iso_utc_now)"
  if [[ "$class" == "stale" && -f "$path" ]]; then
    epoch="$(tr -d '\r' <"$path" | jq -r '.owner_epoch // 0')"
    epoch=$((epoch + 1))
  fi
  write_lease_atomic "$path" "$(jq -n \
    --arg run_id "$run_id" \
    --argjson pid "$$" \
    --arg started_at "$now" \
    --arg heartbeat_at "$now" \
    --argjson owner_epoch "$epoch" \
    '{run_id:$run_id,pid:$pid,started_at:$started_at,heartbeat_at:$heartbeat_at,owner_epoch:$owner_epoch,state:"active"}')"
  printf 'acquired run_id=%s owner_epoch=%d\n' "$run_id" "$epoch"
}

cmd_heartbeat() {
  local path="" run_id="" owner_epoch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lease-path) path="$2"; shift 2 ;;
      --run-id) run_id="$2"; shift 2 ;;
      --owner-epoch) owner_epoch="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  [[ -n "$path" && -n "$run_id" && -n "$owner_epoch" ]] || { usage >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; return 1; }
  [[ -f "$path" ]] || { echo "ERROR: lease missing" >&2; return 1; }

  local on_disk
  on_disk="$(tr -d '\r' <"$path" | jq -r '.owner_epoch // 0')"
  if [[ "$on_disk" != "$owner_epoch" ]]; then
    echo "ERROR: owner_epoch mismatch (held=$on_disk expected=$owner_epoch) — fenced" >&2
    return 2
  fi
  local held
  held="$(tr -d '\r' <"$path" | jq -r '.run_id // ""')"
  if [[ "$held" != "$run_id" ]]; then
    echo "ERROR: run_id mismatch" >&2
    return 1
  fi

  local prev now hb_s now_s next_hb
  prev="$(tr -d '\r' <"$path" | jq -r '.heartbeat_at')"
  now="$(iso_utc_now)"
  hb_s="$(epoch_seconds "$prev")"
  now_s="$(epoch_seconds "$now")"
  if (( now_s < hb_s )); then
    next_hb="$prev"
  else
    next_hb="$now"
  fi
  write_lease_atomic "$path" "$(tr -d '\r' <"$path" | jq --arg hb "$next_hb" '.heartbeat_at = $hb')"
  printf 'heartbeat_at=%s\n' "$next_hb"
}

cmd_release() {
  local path="" run_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lease-path) path="$2"; shift 2 ;;
      --run-id) run_id="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  [[ -n "$path" && -n "$run_id" ]] || { usage >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; return 1; }
  [[ -f "$path" ]] || { echo "ERROR: lease missing" >&2; return 1; }
  local held
  held="$(tr -d '\r' <"$path" | jq -r '.run_id // ""')"
  if [[ "$held" != "$run_id" ]]; then
    echo "ERROR: run_id mismatch" >&2
    return 1
  fi
  write_lease_atomic "$path" "$(tr -d '\r' <"$path" | jq '.state = "released"')"
  printf 'released run_id=%s\n' "$run_id"
}

cmd_classify() {
  local path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lease-path) path="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  [[ -n "$path" ]] || { usage >&2; return 1; }
  lease_classify_state "$path"
}

cmd_adopt() {
  local path="" run_id="" expected_epoch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lease-path) path="$2"; shift 2 ;;
      --run-id) run_id="$2"; shift 2 ;;
      --expected-epoch) expected_epoch="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  [[ -n "$path" && -n "$run_id" && -n "$expected_epoch" ]] || { usage >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; return 1; }

  local class on_disk
  class="$(lease_classify_state "$path")"
  case "$class" in
    live)
      local holder hb
      holder="$(tr -d '\r' <"$path" | jq -r '.run_id // "unknown"')"
      hb="$(tr -d '\r' <"$path" | jq -r '.heartbeat_at // "unknown"')"
      echo "ERROR: cannot adopt live lease run_id=$holder heartbeat_at=$hb" >&2
      return 2
      ;;
    missing)
      echo "ERROR: no lease to adopt" >&2
      return 3
      ;;
    stale) ;;
    released)
      echo "ERROR: cannot adopt a released lease" >&2
      return 1
      ;;
    *)
      echo "ERROR: unexpected lease state: $class" >&2
      return 1
      ;;
  esac
  on_disk="$(tr -d '\r' <"$path" | jq -r '.owner_epoch // 0')"
  if [[ "$on_disk" != "$expected_epoch" ]]; then
    echo "ERROR: compare-and-set failed (on_disk=$on_disk expected=$expected_epoch)" >&2
    return 1
  fi
  local now new_epoch=$((expected_epoch + 1))
  now="$(iso_utc_now)"
  write_lease_atomic "$path" "$(jq -n \
    --arg run_id "$run_id" \
    --argjson pid "$$" \
    --arg started_at "$now" \
    --arg heartbeat_at "$now" \
    --argjson owner_epoch "$new_epoch" \
    '{run_id:$run_id,pid:$pid,started_at:$started_at,heartbeat_at:$heartbeat_at,owner_epoch:$owner_epoch,state:"active"}')"
  printf 'adopted run_id=%s owner_epoch=%d (from %s)\n' "$run_id" "$new_epoch" "$expected_epoch"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    -h | --help | "") usage; exit 0 ;;
    acquire) cmd_acquire "$@" ;;
    heartbeat) cmd_heartbeat "$@" ;;
    release) cmd_release "$@" ;;
    classify) cmd_classify "$@" ;;
    adopt) cmd_adopt "$@" ;;
    *) echo "ERROR: unknown subcommand: $cmd" >&2; usage >&2; exit 1 ;;
  esac
}

main "$@"
