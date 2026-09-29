#!/usr/bin/env bash
# Measure the four hook-log rows #3757 names.
#
# Prints a capture for the host it is actually running on. A Linux run is
# labeled host: linux. It does not write a Windows Git Bash figure. Paste a
# capture whose first host line is `windows-git-bash` into
# reference/hook-log-budget.md to replace `windows-git-bash: unmeasured`.
#
# Every hook run goes through the registered launcher, `node exec-bash.mjs
# --require-true SESSION_EVENT_LOG_ENABLED session-event-log.sh`, the command
# hooks/hooks.json registers: a disabled row is node and the closed gate, an
# enabled row is node, then bash, then the script.
#
#   measure-hook-log-budget.sh [--samples N] [--record <file>]
#   measure-hook-log-budget.sh --check-doc <file>
#
# Exit: 0 capture or a doc that still owes Windows or carries a stamped
# Windows capture; 1 the doc claims a Windows figure without that stamp;
# 2 usage.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-event-log.sh"
LAUNCHER="$SCRIPT_DIR/exec-bash.mjs"
SAMPLES=5
RECORD=""
CHECK_DOC=""

usage() {
  cat <<'EOF'
measure-hook-log-budget.sh — four hook-log probes (#3757).

Usage:
  measure-hook-log-budget.sh [--samples N] [--record <file>]
  measure-hook-log-budget.sh --check-doc <file>

The capture's host line is this machine. Windows Git Bash figures are
produced only when OSTYPE is msys or cygwin. --check-doc accepts a budget
doc that still says `windows-git-bash: unmeasured`, or one that contains
`host: windows-git-bash`. The probes need node on PATH.
EOF
}

need_value() {
  if [[ $# -lt 2 || -z "$2" ]]; then
    echo "ERROR: $1 needs a value" >&2
    usage >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --samples)
    need_value "$@"
    SAMPLES="$2"
    shift 2
    ;;
  --record)
    need_value "$@"
    RECORD="$2"
    shift 2
    ;;
  --check-doc)
    need_value "$@"
    CHECK_DOC="$2"
    shift 2
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -n "$CHECK_DOC" ]]; then
  if [[ ! -f "$CHECK_DOC" ]]; then
    echo "ERROR: doc not found: $CHECK_DOC" >&2
    exit 2
  fi
  missing=0
  for needle in '**Claim:**' '**Basis:**' '**As of:**' '**Recheck:**' 'kill-switch' 'append' 'ls -t' 'late-EOF'; do
    if ! grep -q -F "$needle" "$CHECK_DOC"; then
      echo "missing: $needle" >&2
      missing=1
    fi
  done
  if grep -q -E '^host: windows-git-bash$' "$CHECK_DOC"; then
    echo "doc: windows capture stamped"
  elif grep -q -F 'windows-git-bash: unmeasured' "$CHECK_DOC"; then
    echo "doc: windows figures unmeasured"
  else
    echo "missing: windows-git-bash stamp or unmeasured placeholder" >&2
    missing=1
  fi
  if [[ "$missing" -eq 0 ]]; then
    exit 0
  fi
  exit 1
fi

if [[ ! "$SAMPLES" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --samples needs a positive integer" >&2
  exit 2
fi
if [[ ! -f "$HOOK" || ! -f "$LAUNCHER" ]]; then
  echo "ERROR: hook or launcher not found next to this script" >&2
  exit 2
fi
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node is not on PATH; the registered hook rows start through node" >&2
  exit 2
fi

host_kind() {
  case "${OSTYPE:-}" in
  msys* | cygwin*) printf 'windows-git-bash' ;;
  linux*) printf 'linux' ;;
  darwin*) printf 'macos' ;;
  *) printf 'other' ;;
  esac
}

median_of() {
  sort -n "$1" | awk '
    { a[++n] = $1 }
    END {
      if (n == 0) { print 0; exit }
      if (n % 2 == 1) print a[(n + 1) / 2]
      else print int((a[n / 2] + a[n / 2 + 1]) / 2)
    }
  '
}

elapsed_ms() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%d\n", (b - a) * 1000 }'
}

time_ms() {
  local t0 t1
  t0=$EPOCHREALTIME
  "$@" >/dev/null 2>&1
  t1=$EPOCHREALTIME
  elapsed_ms "$t0" "$t1"
}

median_ms() {
  local i=0
  : >"$samples_file"
  while [[ "$i" -lt "$SAMPLES" ]]; do
    time_ms "$@" >>"$samples_file"
    i=$((i + 1))
  done
  median_of "$samples_file"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PROJ="$WORK/proj"
mkdir -p "$PROJ/.git"
PAYLOAD="$WORK/payload.json"
printf '%s' '{"session_id":"budget","cwd":"/x","hook_event_name":"PostToolUse","tool_name":"Read"}' >"$PAYLOAD"
STOP_PAYLOAD="$WORK/stop.json"
printf '%s' '{"session_id":"budget","cwd":"/x","hook_event_name":"Stop"}' >"$STOP_PAYLOAD"
samples_file="$WORK/samples.txt"

# One registered hook row: $1 the payload file, $2 the option value (true opens the gate).
run_row() {
  env -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED="$2" \
    CLAUDE_PROJECT_DIR="$PROJ" \
    node "$LAUNCHER" --require-true SESSION_EVENT_LOG_ENABLED "$HOOK" <"$1"
}

node_floor="$(median_ms node -e 0)"
bash_floor="$(median_ms bash -c :)"
kill_off="$(median_ms run_row "$PAYLOAD" false)"

wall_ms() {
  local value="$1" t0 t1 n=0
  t0=$EPOCHREALTIME
  while [[ "$n" -lt 15 ]]; do
    run_row "$PAYLOAD" "$value" &
    run_row "$STOP_PAYLOAD" "$value" &
    n=$((n + 1))
  done
  wait
  t1=$EPOCHREALTIME
  elapsed_ms "$t0" "$t1"
}

wall_off="$(wall_ms false)"
wall_on="$(wall_ms true)"

append_probe() {
  local bytes="$1"
  local file="$WORK/append-$bytes"
  local pad i
  : >"$file"
  pad="$(head -c "$bytes" /dev/zero | tr '\0' 'a')"
  i=1
  while [[ "$i" -le 33 ]]; do
    printf '{"i":%s,"pad":"%s"}\n' "$i" "$pad" >>"$file" &
    i=$((i + 1))
  done
  wait
  local lines=0 corrupt=0 line
  lines="$(wc -l <"$file" | tr -d ' ')"
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      if ! printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
        corrupt=$((corrupt + 1))
      fi
    done <"$file"
  else
    corrupt="-1"
  fi
  printf '%s %s' "$lines" "$corrupt"
}

read -r append4_lines append4_corrupt <<<"$(append_probe 4096)"
read -r append16_lines append16_corrupt <<<"$(append_probe 16384)"

LS_DIR="$WORK/lst"
mkdir -p "$LS_DIR"
: >"$LS_DIR/first"
: >"$LS_DIR/second"
stamp="$(date +%Y%m%d%H%M.%S)"
if touch -t "$stamp" "$LS_DIR/first" "$LS_DIR/second"; then
  # shellcheck disable=SC2012 # ls -t is the ordering under measurement, not a file listing
  ls_order="$(ls -t "$LS_DIR" | tr '\n' ' ' | sed 's/ $//')"
  if command -v python3 >/dev/null 2>&1; then
    ls_resolution="$(python3 - "$LS_DIR/first" "$LS_DIR/second" <<'PY'
import os, sys
a = int(os.stat(sys.argv[1]).st_mtime)
b = int(os.stat(sys.argv[2]).st_mtime)
print("same-second" if a == b else "distinct-seconds")
PY
)"
  else
    ls_resolution="python-missing"
  fi
else
  ls_order="touch-failed"
  ls_resolution="touch-failed"
fi

late_eof="$(
  {
    printf '%s' "$(cat "$PAYLOAD")"
    sleep 3
  } | {
    t0=$EPOCHREALTIME
    env -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED=true \
      CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1 CLAUDE_PROJECT_DIR="$PROJ" \
      node "$LAUNCHER" --require-true SESSION_EVENT_LOG_ENABLED "$HOOK" >/dev/null 2>&1
    t1=$EPOCHREALTIME
    elapsed_ms "$t0" "$t1"
  }
)"

HOST="$(host_kind)"
WHEN="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
capture="$(cat <<EOF
host: $HOST
ostype: ${OSTYPE:-unknown}
date: $WHEN
samples: $SAMPLES
node_spawn_floor_median_ms: $node_floor
bash_spawn_floor_median_ms: $bash_floor
kill_switch_off_median_ms: $kill_off
parallel_wall_off_ms: $wall_off
parallel_wall_on_ms: $wall_on
append_4kb_lines: $append4_lines
append_4kb_corrupt: $append4_corrupt
append_16kb_lines: $append16_lines
append_16kb_corrupt: $append16_corrupt
ls_t_order: $ls_order
ls_t_resolution: $ls_resolution
late_eof_ms: $late_eof
EOF
)"

printf '%s\n' "$capture"
if [[ -n "$RECORD" ]]; then
  printf '%s\n' "$capture" >"$RECORD"
fi
exit 0
