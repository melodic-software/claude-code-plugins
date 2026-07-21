#!/usr/bin/env bash
# Test entry for the babysit-prs engine: runs the stdlib-unittest suite under
# tests/, an optional ruff lint pass, and a bash-level check of the guarded
# wrappers (whose --allow-unpinned-head rejection is a shell concern, not a
# Python one). SKIPs (exit 0) when Python 3.11+ is unavailable, matching the
# repo test-runner convention for optional toolchains.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
      PY="$candidate"
      break
    fi
  fi
done

if [[ -z "$PY" ]]; then
  echo "SKIP: Python 3.11+ not found"
  exit 0
fi

FAILED=0

echo "== unittest suite =="
if ! "$PY" -m unittest discover -s tests -p 'test_*.py'; then
  FAILED=1
fi

if command -v ruff >/dev/null 2>&1; then
  echo "== ruff =="
  if ! ruff check . tests; then
    FAILED=1
  fi
else
  echo "SKIP: ruff not installed (lint pass omitted)"
fi

echo "== guarded-wrapper behavior =="
MERGE_WRAPPER="../../../bin/source-control-babysit-merge"
RESOLVE_WRAPPER="../../../bin/source-control-babysit-resolve-thread"

check_exit() {
  local label="$1" want="$2"
  shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (want exit $want, got $got)" >&2
    FAILED=1
  fi
}

# The wrapper refuses the interactive unpinned override so no allow-rule-covered
# invocation can merge an unvetted head.
check_exit "merge wrapper rejects --allow-unpinned-head" 2 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --merge --allow-unpinned-head
# The wrapper reaches the fail-closed CLI when no allowlist is supplied.
check_exit "merge wrapper reaches fail-closed CLI (no allowlist)" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1"
check_exit "resolve wrapper reaches fail-closed CLI (no allowlist)" 3 \
  bash "$RESOLVE_WRAPPER" "owner/repo#1"
# The autopilot merge tier is fail-closed at the wrapper: the umbrella flag
# without its three required sets refuses before any network access.
check_exit "merge wrapper rejects --autopilot-merge-tier without required sets" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners owner --autopilot-merge-tier

exit "$FAILED"
