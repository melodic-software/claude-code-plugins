#!/usr/bin/env bash
# Exit codes:
#   0  armed
#   3  invalid argument
#   4  prerequisite missing (jq), or no plugins/cache install anchor — a
#      --plugin-dir checkout install has no trusted record store, so arming is
#      refused rather than degraded to a forgeable location
#   5  managed settings veto: an organization configured
#      lane_stop_gate_enabled=false at the managed scope, which outranks any
#      per-session arming — the launch should fail visibly, not run ungated

set -uo pipefail
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=lane-stop-gate-lib.sh
source "$HOOK_DIR/lane-stop-gate-lib.sh"
err() { printf 'ERROR: lane-stop-gate-arm: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Arm the lane-stop gate for one session; run by the lane launcher before launch.
Usage: lane-stop-gate-arm.sh --id <arm-id> [--cwd DIR] [--sentinel TOK] [--marker PATH]
  --id        record id, 8-64 chars of [A-Za-z0-9_-] (caller-generated, random)
  --cwd       the lane's working directory (diagnostic only)
  --sentinel  per-session completion token
  --marker    per-session completion-marker path
Exit: 0 armed; 3 invalid argument; 4 jq missing or no plugins/cache install anchor;
5 managed settings disable the gate.
EOF
}

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

_arm_root=""
gate_plugin_root_to _arm_root "$HOOK_DIR"
if ! gate_resolve_anchor "$_arm_root"; then
  err "no plugins/cache install anchor for $HOOK_DIR — a --plugin-dir checkout install has no trusted record store, so the gate cannot be armed (managed settings remain the only enable path there)"
  exit 4
fi

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

find "$DIR" -type f -mtime +"$GATE_ARM_TTL_DAYS" -delete 2>/dev/null

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
