#!/usr/bin/env bash
# evaluate-schedule-precondition.sh — evaluate a recurring schedule row precondition.
#
# Usage:
#   evaluate-schedule-precondition.sh <schedule.json> <item-id> [--operator-confirmed]
#
# Prints: met | unmet | needs-confirmation | no-precondition
# Exit: 0 met/no-precondition; 1 unmet; 2 needs-confirmation

set -euo pipefail

SCHEDULE="${1:-}"
ITEM_ID="${2:-}"
OPERATOR_CONFIRMED=0
shift 2 || true
while [[ $# -gt 0 ]]; do
  case "$1" in
  --operator-confirmed)
    OPERATOR_CONFIRMED=1
    shift
    ;;
  *)
    echo "ERROR: unknown flag: $1" >&2
    exit 1
    ;;
  esac
done

[[ -n "$SCHEDULE" && -n "$ITEM_ID" ]] || {
  echo "Usage: evaluate-schedule-precondition.sh <schedule.json> <item-id> [--operator-confirmed]" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq required" >&2
  exit 1
}
[[ -f "$SCHEDULE" ]] || {
  echo "ERROR: schedule not found: $SCHEDULE" >&2
  exit 1
}

row="$(jq -c --arg id "$ITEM_ID" '.items[] | select(.id == $id)' "$SCHEDULE")"
[[ -n "$row" ]] || {
  echo "ERROR: no schedule row with id=$ITEM_ID" >&2
  exit 1
}

has_precond="$(jq -r 'has("precondition")' <<<"$row")"
if [[ "$has_precond" != "true" ]]; then
  echo "no-precondition"
  exit 0
fi

precond_id="$(jq -r '.precondition.id // empty' <<<"$row")"
requires_confirm="$(jq -r '.precondition.requires_operator_confirmation // false' <<<"$row")"

case "$precond_id" in
frontier-release-since-last-checked)
  if [[ "$requires_confirm" == "true" && "$OPERATOR_CONFIRMED" -eq 0 ]]; then
    # The printf wrapper is load-bearing, not redundant: command substitution
    # collapses trailing newlines to one, so a prompt authored with a trailing
    # blank line prints the same single separator as any other. Emitting jq's
    # output directly passes those newlines through and puts a blank line before
    # the marker below. Measured over 7 prompt shapes, 2 diverge.
    printf '%s\n' "$(jq -r '.precondition.prompt // "precondition unmet"' <<<"$row")"
    echo "needs-confirmation"
    exit 2
  fi
  echo "met"
  exit 0
  ;;
*)
  printf 'ERROR: unknown precondition id: %s\n' "$precond_id" >&2
  echo "unmet"
  exit 1
  ;;
esac
