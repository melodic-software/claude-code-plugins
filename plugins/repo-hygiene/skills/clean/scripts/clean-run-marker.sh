#!/usr/bin/env bash
# Opens, closes or reports the per-session run-open marker that scopes the clean
# skill's destructive guard (destructive-guard.sh) to a mutating clean run.
#
# Usage:
#   clean-run-marker.sh open  --tier <tier> --session <id> --data-dir <dir>
#   clean-run-marker.sh close --session <id> --data-dir <dir>
#   clean-run-marker.sh --help
#
# open writes the marker for every tier except the read-only scan and
# scan-batch, which never arm the guard (it prints "not armed" and writes
# nothing). close removes it and succeeds when it is already gone. The marker
# lives under <dir>/clean-run/<id>.open; the guard reads the same path from
# CLAUDE_PLUGIN_DATA and the hook input's session_id.
#
# Exit: 0 success; 2 usage error or an unusable --session / --data-dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/run-marker.sh
source "$SCRIPT_DIR/lib/run-marker.sh"

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

ACTION="${1:-}"
case "$ACTION" in
open | close) shift ;;
--help | -h)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

TIER="" SESSION="" DATA_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --tier)
    TIER="${2:-}"
    shift 2 || shift
    ;;
  --session)
    SESSION="${2:-}"
    shift 2 || shift
    ;;
  --data-dir)
    DATA_DIR="${2:-}"
    shift 2 || shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "Error: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

if [[ "$ACTION" == open ]]; then
  if [[ -z "$TIER" ]]; then
    echo "Error: open needs --tier" >&2
    exit 2
  fi
  case "$TIER" in
  scan | scan-batch)
    echo "Marker: not armed (read-only tier: $TIER)"
    exit 0
    ;;
  esac
fi

if ! run_marker_path_to MARKER "$DATA_DIR" "$SESSION"; then
  echo "Error: --data-dir and --session must both resolve (session ids use letters, digits, _ and -); the destructive guard cannot be scoped to this run." >&2
  exit 2
fi

if [[ "$ACTION" == open ]]; then
  if ! run_marker_write "$MARKER"; then
    echo "Error: could not write the run marker: $MARKER" >&2
    exit 2
  fi
  echo "Marker: armed ($MARKER)"
else
  rm -f "$MARKER"
  echo "Marker: cleared"
fi
