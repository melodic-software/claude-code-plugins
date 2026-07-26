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

# Exit 2 on this path is overloaded: it is both the wrapper's own refusal AND
# argparse's usage/unrecognized-argument error for the CLI it wraps. A
# code-only assertion cannot distinguish "the wrapper held the boundary" from
# "the wrapper let it through and argparse happened to also reject it" -- the
# --allow-unpinned-head=true spelling is exactly that trap (#1522). This
# helper asserts on the wrapper's own refusal text on stderr, not just the
# exit code.
check_wrapper_refusal() {
  local label="$1"
  shift
  local stderr got
  stderr="$(bash "$MERGE_WRAPPER" "$@" 2>&1 >/dev/null)"
  got=$?
  if [[ "$got" == "2" && "$stderr" == *"is not permitted through the wrapper"* ]]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (want exit 2 + wrapper refusal text, got $got: $stderr)" >&2
    FAILED=1
  fi
}

# The wrapper refuses the interactive unpinned override so no allow-rule-covered
# invocation can merge an unvetted head.
check_wrapper_refusal "merge wrapper rejects --allow-unpinned-head" \
  "owner/repo#1" --merge --allow-unpinned-head
# The wrapper refuses a long-option prefix too (allow_abbrev on the CLI would
# otherwise resolve it to the guarded flag behind the wrapper's back).
check_wrapper_refusal "merge wrapper rejects --allow-unpinned-hea (prefix spelling)" \
  "owner/repo#1" --merge --allow-unpinned-hea
# The wrapper refuses the =value spelling of the flag and of a prefix of it --
# the prefix comparison alone missed this because "--allow-unpinned-head=true"
# is not itself a prefix of "--allow-unpinned-head" (#1522).
check_wrapper_refusal "merge wrapper rejects --allow-unpinned-head=true (=value spelling)" \
  "owner/repo#1" --merge --allow-unpinned-head=true
check_wrapper_refusal "merge wrapper rejects --allow-unpinned=1 (=value prefix spelling)" \
  "owner/repo#1" --merge --allow-unpinned=1
check_wrapper_refusal "merge wrapper rejects --allow-unpinned-hea=1 (=value prefix spelling)" \
  "owner/repo#1" --merge --allow-unpinned-hea=1
# No over-refusal: sibling flags that share the --allow prefix, including with
# an =value tail, still reach the fail-closed CLI rather than the wrapper.
# --allowed-owners deliberately names an owner NOT in scope, so the owner-scope
# refusal fires and the assertion holds without any network call.
check_exit "merge wrapper does not over-refuse --allow-dependency" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners someone-else --allow-dependency
check_exit "merge wrapper does not over-refuse --allow-unprotected" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners someone-else --allow-unprotected
check_exit "merge wrapper does not over-refuse --allowed-owners=owner" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners=someone-else
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
