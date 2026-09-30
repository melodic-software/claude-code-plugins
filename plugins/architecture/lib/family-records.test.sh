#!/usr/bin/env bash
# Tests for is_family_record: every name the map-* renderers and skills write
# is recognized, and configuration names are not.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/../skills"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/family-records.sh"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

written="$(
  grep -hoE '\$\{?(out|outdir|OUT)\}?"?/[a-z-]+\.[a-z]+' "$SKILLS_DIR"/*/scripts/render-*.sh | sed 's|.*/||'
  grep -hoE '<architecture_dir>/[a-z-]+\.(json|md|dsl|dbml)' "$SKILLS_DIR"/*/SKILL.md | sed 's|.*/||'
)"
written="$(printf '%s\n' "$written" | grep -v -- '-notes\.md$' | sort -u)"

if [[ "$(printf '%s\n' "$written" | wc -l)" -ge 13 ]]; then
  pass "renderers and skills name at least 13 outputs"
else
  fail "the scan found too few output names, the grep patterns no longer match the renderers"
fi

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if is_family_record "$name"; then pass "recognized: $name"; else fail "family output not in is_family_record: $name"; fi
done <<<"$written"

for name in appsettings.json package.json package-lock.json dependencies.md landscape-notes.md components-notes.md docker-compose.yml; do
  if is_family_record "$name"; then fail "not a family record: $name"; else pass "not a family record: $name"; fi
done

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
