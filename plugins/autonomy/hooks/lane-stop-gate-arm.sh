#!/usr/bin/env bash
# lane-stop-gate-arm.sh — operator-side per-session arming for the lane-stop
# gate (#1784). Run by the lane launcher (or an operator) BEFORE launching a
# session that should be gated; never by the watched session itself.
#
# Writes an arm record — the per-session trusted-config source the gate resolves
# between managed and user settings — under this plugin's own install-derived
# data directory: <config>/plugins/data/<id>/lane-arms/<arm-id>. The launcher
# then passes the same arm id to the session through the `lane_stop_gate_arm_id`
# userConfig option (`claude --settings ...`), and the gate treats the
# env-delivered id purely as a pointer into this store. Because the store is
# derived from this script's own location — never from an environment value — a
# watched repository cannot mint, redirect, or forge a record; because the id is
# random and the gate claims it for the first presenting session, a replayed id
# is worthless.
#
# Usage:
#   lane-stop-gate-arm.sh --id <arm-id> [--cwd DIR] [--sentinel TOK] [--marker PATH]
#
#   --id        record id, 8-64 chars of [A-Za-z0-9_-] (caller-generated, random)
#   --cwd       the lane's working directory (recorded as a diagnostic; the id,
#               not the cwd, is the record's identity)
#   --sentinel  per-session completion token (else the gate's resolution
#               continues to user settings / the LANE-STOP-OK default)
#   --marker    per-session completion-marker path
#
# Exit codes:
#   0  armed
#   3  invalid argument
#   4  prerequisite missing (jq), or no plugins/cache install anchor — a
#      --plugin-dir checkout install has no trusted record store, so arming is
#      refused rather than degraded to a forgeable location
#   5  managed settings veto: an organization configured
#      lane_stop_gate_enabled=false at the managed scope, which outranks any
#      per-session arming — the launch should fail visibly, not run ungated
#
# Fail direction: this helper fails CLOSED (refuse to arm, so the launcher can
# refuse to launch) — the operator is present at launch time. The gate itself
# stays fail-open at stop time.

set -uo pipefail

# shellcheck source=lane-stop-gate-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lane-stop-gate-lib.sh"

err() { printf 'ERROR: lane-stop-gate-arm: %s\n' "$*" >&2; }

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

ID=""
CWD=""
SENTINEL=""
MARKER=""
SENTINEL_SET=0
MARKER_SET=0

while (($#)); do
  case "$1" in
  --id)
    ID="${2:-}"
    shift
    ;;
  --cwd)
    CWD="${2:-}"
    shift
    ;;
  --sentinel)
    SENTINEL="${2:-}"
    SENTINEL_SET=1
    shift
    ;;
  --marker)
    MARKER="${2:-}"
    MARKER_SET=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown argument: $1"
    exit 3
    ;;
  esac
  shift
done

if ! [[ "$ID" =~ $GATE_ARM_ID_RE ]]; then
  err "--id is required: 8-64 characters of [A-Za-z0-9_-]"
  exit 3
fi

command -v jq >/dev/null 2>&1 || {
  err "jq not found (required to write the arm record)"
  exit 4
}

if ! gate_resolve_anchor "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"; then
  err "no plugins/cache install anchor for $(dirname -- "${BASH_SOURCE[0]}") — a --plugin-dir checkout install has no trusted record store, so the gate cannot be armed (managed settings remain the only enable path there)"
  exit 4
fi

# Managed veto: an org-scope explicit false outranks per-session arming. Checked
# here so the refusal is visible at launch time, and re-checked by the gate.
if v=$(gate_managed_option lane_stop_gate_enabled) && [[ "$v" == "false" ]]; then
  err "managed settings configure lane_stop_gate_enabled=false — arming is vetoed by organization policy"
  exit 5
fi

RECORD=$(gate_arm_record_path "$ID") || {
  err "could not derive the arm-record path"
  exit 4
}
DIR="${RECORD%/*}"
mkdir -p -- "$DIR" 2>/dev/null || {
  err "could not create the arm-record directory: $DIR"
  exit 4
}

# Self-cleaning store: drop records past the gate's TTL so crashed lanes cannot
# accumulate stale grants. Best-effort.
find "$DIR" -type f -mtime +7 -delete 2>/dev/null

# A re-armed id must start UNCLAIMED. The gate's claim sidecar outlives the
# record it names, so a claim left by the previous lane would bind this fresh
# record to a session that no longer exists and the new lane would run ungated.
#
# Cleared BEFORE the record is written, never after: a crash between the two
# then leaves the OLD record with no claim, and the next presenter claims it —
# an extra gated stop. The other order leaves a FRESH record beside a STALE
# claim, which refuses the new lane on every stop until the record ages out.
CLAIM=$(gate_arm_claim_path "$ID") && rm -f -- "$CLAIM" 2>/dev/null

NOW=$(date +%s 2>/dev/null) || NOW=""
[[ "$NOW" =~ ^[0-9]+$ ]] || {
  err "could not read the current epoch time for the record's TTL stamp"
  exit 4
}

TMP="$RECORD.tmp.$$"
if ! jq -n --arg cwd "$CWD" --arg s "$SENTINEL" --argjson ss "$SENTINEL_SET" \
  --arg m "$MARKER" --argjson ms "$MARKER_SET" --argjson t "$NOW" \
  '{v: 1, armed_at: $t}
   + (if $cwd != "" then {cwd: $cwd} else {} end)
   + (if $ss == 1 then {sentinel: $s} else {} end)
   + (if $ms == 1 then {marker: $m} else {} end)' >"$TMP" 2>/dev/null; then
  rm -f -- "$TMP" 2>/dev/null
  err "could not build the arm record"
  exit 4
fi
if ! mv -f -- "$TMP" "$RECORD" 2>/dev/null; then
  rm -f -- "$TMP" 2>/dev/null
  err "could not write the arm record: $RECORD"
  exit 4
fi

printf 'lane-stop-gate armed: record %s\n' "$RECORD" >&2
exit 0
