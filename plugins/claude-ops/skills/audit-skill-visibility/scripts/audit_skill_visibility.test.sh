#!/usr/bin/env bash
# Cross-platform contract wrapper for the skill-starvation engine test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the engine. Parse it rather
# than restating the number here.
ENGINE="$SCRIPT_DIR/audit_skill_visibility.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

"$PYTHON" -c "import sys; floor = tuple(int(p) for p in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" || {
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
}

(cd "$SCRIPT_DIR" && "$PYTHON" -m unittest -v test_audit_skill_visibility)

# Contract check: the shipped fixture must resolve every row to not-observable.
# A fresh install is exactly where a naive report libels the fleet as unused, so
# this asserts the honesty floor end-to-end, not just in the unit seam.
FIXTURE="$SCRIPT_DIR/../tests/fixtures/fleet-basic.json"
OUT="$("$PYTHON" "$ENGINE" --fixture "$FIXTURE" --render json)"
TOTAL="$(printf '%s' "$OUT" | "$PYTHON" -c 'import json,sys; print(len(json.load(sys.stdin)["skills"]))')"
UNOBS="$(printf '%s' "$OUT" | "$PYTHON" -c 'import json,sys; m=json.load(sys.stdin); print(sum(1 for s in m["skills"] if s["observation"]["value"]=="not-observable"))')"
if [[ "$TOTAL" != "$UNOBS" ]]; then
  echo "FAIL: fresh-install fixture resolved $UNOBS/$TOTAL rows not-observable; expected all" >&2
  exit 1
fi
echo "ok: fresh-install fixture withheld every cold verdict ($UNOBS/$TOTAL)"
