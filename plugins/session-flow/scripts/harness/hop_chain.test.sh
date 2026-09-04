#!/usr/bin/env bash
# Contract tests for hop_chain.py: runs its --dry-run self-test and its
# --budget projection. Neither mode reaches the API, so this suite spends
# nothing; the live hop-chain run is an operator action, never a test.
#
# SKIPs (exit 0) when Python 3.10+ is unavailable, matching the repo test-runner
# convention for optional toolchains (save_point.test.sh is the precedent).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PY="$candidate"
    break
  fi
done

if [[ -z "$PY" ]]; then
  echo "SKIP: Python 3.10+ not found"
  exit 0
fi

status=0

echo "== hop_chain.py --dry-run"
if ! "$PY" -X utf8 hop_chain.py --dry-run; then
  echo "FAIL: --dry-run self-test"
  status=1
fi

# --budget writes a 20-hop chain; give it its own scratch dir in mixed form so
# the native interpreter reads the same path Git Bash printed (windows-path-emit).
work="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then
  work="$(cygpath -m "$work")"
fi

echo "== hop_chain.py --budget"
if ! "$PY" -X utf8 hop_chain.py --budget --work-dir "$work"; then
  echo "FAIL: --budget projection"
  status=1
fi
rm -rf "$work"

if [[ "$status" -eq 0 ]]; then
  echo "PASS: hop_chain.py contract tests"
fi
exit "$status"
