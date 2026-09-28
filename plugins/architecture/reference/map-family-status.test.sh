#!/usr/bin/env bash
# The status page must name every child skill and must not claim it is on main.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PAGE="$ROOT/plugins/architecture/reference/map-family-status.md"
SKILLS="$ROOT/plugins/architecture/skills"
FAILED=0

fail() {
  echo "FAIL: $1" >&2
  FAILED=$((FAILED + 1))
}

[[ -f "$PAGE" ]] || fail "status page missing"

for skill in map-dependencies map-components map-context map-containers map-flow map-events map-data map-deployment map-states; do
  if ! grep -q "$skill" "$PAGE"; then
    fail "status page does not name $skill"
  fi
  if [[ -d "$SKILLS/$skill" ]]; then
    fail "$skill is on main; the status page must be rewritten before it claims the skill is absent"
  fi
done

if ! grep -q 'map-landscape' "$PAGE"; then
  fail "status page does not keep map-landscape as the in-tree skill"
fi
if [[ ! -d "$SKILLS/map-landscape" ]]; then
  fail "map-landscape is missing from skills/"
fi
if ! grep -q 'not in this tree' "$PAGE"; then
  fail "status page does not say the child skills are absent from this tree"
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "map-family-status.test.sh: all passed"
  exit 0
fi
echo "$FAILED check(s) failed" >&2
exit 1
