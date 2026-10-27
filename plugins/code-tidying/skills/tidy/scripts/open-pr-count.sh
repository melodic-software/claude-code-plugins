#!/usr/bin/env bash
# Open chore/tidy-* PR count for the backlog throttle.
#
# -e omitted: fact-gatherer must capture gh's exit code, not abort on it.
# -o pipefail omitted: graceful degradation when gh fails mid-pipeline.
set -u

THROTTLE_LIMIT=3
# Open PRs are listed without a search and filtered by head branch here: a
# degraded search can answer a false empty with no signal gh passes on. A
# listing that fills its limit may be missing tidy PRs, so it throttles.
LIST_LIMIT=1000

usage() {
  cat <<EOF
open-pr-count.sh — count open chore/tidy-* PRs (backlog-throttle facts).

Throttle active when count >= ${THROTTLE_LIMIT} and gh exit 0, or when the
open-PR listing reaches its ${LIST_LIMIT}-PR limit.

Usage:
  open-pr-count.sh [--help]

Exit: 0 gh ok; 1 gh failed (count unknown).
EOF
}

emit_unknown() {
  printf 'Open tidy PR count: unknown\n'
  printf 'Throttle active: unknown\n'
  printf 'Detail: %s\n' "$1"
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  emit_unknown "gh not installed"
  exit 1
fi

counts="$(gh pr list --state open --limit "$LIST_LIMIT" --json headRefName \
  --jq '"\(length) \(map(select(.headRefName | startswith("chore/tidy-"))) | length)"' 2>/dev/null | tr -d '\r')"
if [[ ! "$counts" =~ ^[0-9]+\ [0-9]+$ ]]; then
  emit_unknown "gh pr list failed"
  exit 1
fi
listed="${counts% *}"
count="${counts#* }"

if [[ "$listed" -ge "$LIST_LIMIT" ]]; then
  printf 'Open tidy PR count: %s or more\n' "$count"
  printf 'Throttle active: yes\n'
  printf 'Detail: the open-PR listing reached its %s-PR limit; the count may be higher\n' "$LIST_LIMIT"
  exit 0
fi

printf 'Open tidy PR count: %s\n' "$count"
if [[ "$count" -ge "$THROTTLE_LIMIT" ]]; then
  printf 'Throttle active: yes\n'
  printf 'Detail: backlog >= %s\n' "$THROTTLE_LIMIT"
else
  printf 'Throttle active: no\n'
  printf 'Detail: backlog below %s\n' "$THROTTLE_LIMIT"
fi
exit 0
