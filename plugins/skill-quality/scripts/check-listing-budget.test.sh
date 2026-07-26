#!/usr/bin/env bash
# Black-box contract test for check-listing-budget.sh.
#
# Self-contained and cwd-independent: builds a throwaway git repo with fixture
# skill roots, runs the reporter, and asserts on exit code + output.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-listing-budget.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX 2>/dev/null || true
git -C "$TMP" init -q
git -C "$TMP" config user.email test@example.com
git -C "$TMP" config user.name test

ROOT_A="$TMP/plugin-a/skills"

make_skill() {
  local root="$1" name="$2" desc="$3" wtu="${4:-}"
  mkdir -p "$root/$name"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: "%s"\n' "$desc"
    [[ -n "$wtu" ]] && printf 'when_to_use: "%s"\n' "$wtu"
    printf -- '---\n\n## Purpose\n\nFixture.\n'
  } >"$root/$name/SKILL.md"
}

run() { (cd "$TMP" && bash "$SUT" "$@"); }

# 1. --help exits 0.
if run --help >/dev/null 2>&1; then
  pass "--help exits 0"
else
  fail "--help should exit 0"
fi

# 2. No matching root at all is a usage/env error (exit 2).
out="$(run "$TMP/does-not-exist" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'no skills root found' <<<"$out"; then
  pass "missing root(s) exits 2 with a clear message"
else
  fail "missing root(s) should exit 2 (rc=$rc): $out"
fi

# 3. A root that exists but has no skills reports zero and exits 0.
mkdir -p "$TMP/empty-root"
out="$(run "$TMP/empty-root" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q '0 skills, nothing to report' <<<"$out"; then
  pass "empty root reports zero skills and exits 0"
else
  fail "empty root should report zero and exit 0 (rc=$rc): $out"
fi

# 4. A small aggregate, well under the default 8000-char budget, is OK and
#    exits 0 — advisory-only, never fails even implicitly.
make_skill "$ROOT_A" small-one "A small fixture skill."
make_skill "$ROOT_A" small-two "Another small fixture skill."
out="$(run "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'CHECK-LISTING-BUDGET: OK' <<<"$out"; then
  pass "small aggregate under the default budget reports OK"
else
  fail "small aggregate should report OK (rc=$rc): $out"
fi

# 5. Forcing a tiny budget via CHECK_SKILL_LISTING_BUDGET_CHARS trips the WARN
#    path — proves the override plumbs through and the check never hardcodes
#    8000 as unconditional ground truth (item 4's caveat).
out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=10 bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: aggregate exceeds the budget' <<<"$out" && grep -q 'CHECK-LISTING-BUDGET: WARN' <<<"$out"; then
  pass "a forced tiny budget trips the WARN path but still exits 0 (advisory only)"
else
  fail "forced tiny budget should WARN and still exit 0 (rc=$rc): $out"
fi

# 6. The joiner is counted: a description + when_to_use entry is exactly
#    DESC_LEN + 3 + WTU_LEN, not DESC_LEN + WTU_LEN (item 2's fix, mirrored
#    here since the aggregate must match what check-skill.sh's check 2 now
#    computes, or the two checks would disagree on the same entry's size).
mkdir -p "$TMP/joiner-root"
desc_40='1234567890123456789012345678901234567890'
wtu_10='1234567890'
make_skill "$TMP/joiner-root" joiner-skill "$desc_40" "$wtu_10"
# Budget set to exactly DESC(40) + WTU(10) = 50 so the un-joined sum would
# read as "OK" (50/50) but the joined sum (53) must WARN (53 > 50).
out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=50 bash "$SUT" "$TMP/joiner-root" 2>&1)"
if grep -q 'aggregate: 53 chars' <<<"$out" && grep -q 'WARN: aggregate exceeds the budget by 3 chars' <<<"$out"; then
  pass "the 3-char description/when_to_use joiner is counted in the aggregate"
else
  fail "aggregate should count the 3-char joiner (expected 53 chars, WARN by 3): $out"
fi

# 7. An oversized single entry is capped at CHECK_SKILL_LISTING_MAX_DESC_CHARS
#    before summing — mirrors the harness's own per-entry truncation, so one
#    already-failing (check 2) entry cannot silently inflate the aggregate
#    past what Claude Code would actually load.
mkdir -p "$TMP/cap-root"
long_desc="$(printf 'x%.0s' {1..200})"
make_skill "$TMP/cap-root" cap-skill "$long_desc"
out="$(cd "$TMP" && CHECK_SKILL_LISTING_MAX_DESC_CHARS=50 CHECK_SKILL_LISTING_BUDGET_CHARS=1000 bash "$SUT" "$TMP/cap-root" 2>&1)"
if grep -q 'aggregate: 50 chars' <<<"$out"; then
  pass "an oversized entry is capped at CHECK_SKILL_LISTING_MAX_DESC_CHARS before summing"
else
  fail "oversized entry should cap at 50 chars, not count all 200 (expected 'aggregate: 50 chars'): $out"
fi

# 8. Multiple roots pool into ONE shared aggregate (the marketplace-repo use
#    case: plugins/*/skills passed as separate positional roots).
mkdir -p "$TMP/root-x" "$TMP/root-y"
make_skill "$TMP/root-x" x-skill "12345"
make_skill "$TMP/root-y" y-skill "67890"
out="$(run "$TMP/root-x" "$TMP/root-y" 2>&1)"
if grep -q 'over 2 skill(s) across 2 root(s)' <<<"$out" && grep -q 'aggregate: 10 chars' <<<"$out"; then
  pass "multiple roots pool into one shared aggregate"
else
  fail "multiple roots should pool into one aggregate of 10 chars across 2 skills: $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
