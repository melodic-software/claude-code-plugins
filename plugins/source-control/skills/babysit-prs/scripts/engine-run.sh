#!/usr/bin/env bash
# One part of the babysit-prs engine's unittest suite, run by engine.test.sh
# (part a) and engine-b.test.sh to engine-d.test.sh: the tests/test_*.py modules
# the case below puts in <part>, in one unittest process. Every module lands in
# exactly one part, so the four parts run the whole suite between them; the
# split keeps each part under the 120 s per-suite budget in CI (scripts/README.md,
# Per-suite time budget in CI). SKIPs (exit 0) when Python 3.11+ is unavailable.
#   bash plugins/source-control/skills/babysit-prs/scripts/engine-run.sh <part>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "$SCRIPT_DIR" || exit 1

part="${1:-}"
if [[ ! "$part" =~ ^[a-d]$ ]]; then
  echo "usage: engine-run.sh <part>, a part being a, b, c or d" >&2
  exit 2
fi

# A part with no wrapper would never run, so its modules would drop out of CI.
for wrapper in engine.test.sh engine-b.test.sh engine-c.test.sh engine-d.test.sh; do
  if [[ ! -f "$wrapper" ]]; then
    echo "FAIL: $wrapper is missing, so its part of tests/ never runs" >&2
    exit 1
  fi
done

PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    PY="$candidate"
    break
  fi
done

if [[ -z "$PY" ]]; then
  echo "SKIP: Python 3.11+ not found"
  exit 0
fi

modules=()
for path in tests/test_*.py; do
  name="${path##*/}"
  case "$name" in
    test_babysit_merge_policy.py) owner=b ;;
    test_babysit_postmerge*.py) owner=c ;;
    test_babysit_*.py) owner=d ;;
    *) owner=a ;;
  esac
  if [[ "$owner" == "$part" ]]; then
    modules+=("tests.${name%.py}")
  fi
done

if [[ "${#modules[@]}" -eq 0 ]]; then
  echo "FAIL: part $part holds no tests/test_*.py module" >&2
  exit 1
fi

echo "== unittest suite, part $part: ${#modules[@]} modules =="
"$PY" -m unittest "${modules[@]}"
