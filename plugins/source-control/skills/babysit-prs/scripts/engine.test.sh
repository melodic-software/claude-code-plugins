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

# check_wrapper_refusal asserts the WRAPPER's own guard fired, not merely that
# something exited 2. Exit 2 is overloaded three ways on this path -- the
# wrapper's refusal, argparse's usage/ambiguity errors, and babysit_merge.py's
# own usage errors -- so a code-only assertion cannot tell a held guard from an
# accidental parse failure. Matching the refusal text is what proves the claim
# the guard contract publishes.
check_wrapper_refusal() {
  local label="$1"
  shift
  local err
  # Redirect order is load-bearing: inside $(...), `2>&1` first points stderr at
  # the capture pipe, then `>/dev/null` discards stdout. The familiar
  # `>/dev/null 2>&1` spelling would discard BOTH and make every row here pass
  # vacuously -- do not "fix" it to that idiom.
  err="$(bash "$MERGE_WRAPPER" "$@" 2>&1 >/dev/null)"
  local got=$?
  if [[ "$got" == 2 && "$err" == *"is not permitted through the wrapper"* ]]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (want exit 2 + wrapper refusal text, got exit $got: $err)" >&2
    FAILED=1
  fi
}

# The wrapper refuses the interactive unpinned override so no allow-rule-covered
# invocation can merge an unvetted head.
check_wrapper_refusal "merge wrapper rejects --allow-unpinned-head" \
  "owner/repo#1" --merge --allow-unpinned-head
# ...and refuses it in every spelling argparse prefix abbreviation would accept
# (#1371). Equality matching here was bypassable by dropping one character:
# `--allow-unpinned-hea` was an unrecognized string to the wrapper and a valid
# spelling of the flag to the CLI, so the refusal the wrapper exists for did not
# hold. The wrapper must refuse independently of what the CLI happens to accept.
# The last row runs the relation the other way: a longer flag that STARTS with
# the guarded one is refused too. allow_abbrev=False would not catch that one --
# it would be a recognized, distinct option -- so only this half can.
for spelling in \
  --allow-unpinned-hea \
  --allow-unpinned-h \
  --allow-unpinned \
  --allow-unpi \
  --allow-unp \
  --allow-u \
  --allow \
  --allow-unpinned-head=1 \
  --allow-unpi=1 \
  --allow-unpinned-head-also; do
  check_wrapper_refusal "merge wrapper rejects $spelling" \
    "owner/repo#1" --merge "$spelling"
done
# No over-refusal of the sibling flags every real invocation carries: these are
# not prefixes of --allow-unpinned-head and must reach the CLI (exit 3, the
# fail-closed allowlist check) rather than tripping the guard.
for sibling in --allow-dependency --allow-unprotected; do
  check_exit "merge wrapper passes $sibling through to the CLI" 3 \
    bash "$MERGE_WRAPPER" "owner/repo#1" "$sibling"
done
check_exit "merge wrapper passes --allowed-owners through to the CLI" 3 \
  bash "$MERGE_WRAPPER" "owner/repo#1" --allowed-owners someone-else
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
