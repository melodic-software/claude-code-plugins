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
  local root="$1" name="$2" desc="$3" wtu="${4:-}" dmi="${5:-}"
  mkdir -p "$root/$name"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: "%s"\n' "$desc"
    [[ -n "$wtu" ]] && printf 'when_to_use: "%s"\n' "$wtu"
    [[ -n "$dmi" ]] && printf 'disable-model-invocation: %s\n' "$dmi"
    printf -- '---\n\n## Purpose\n\nFixture.\n'
  } >"$root/$name/SKILL.md"
}

run() { (cd "$TMP" && bash "$SUT" "$@"); }

# 1. --help exits 0 and prints the WHOLE header block — no clipping, no
#    overrun past the header into code. usage() derives its range from the
#    comment block itself, so adding header lines can never desync it again.
out="$(run --help 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'in the issue this script closes' <<<"$out" &&
  ! grep -q 'set -uo pipefail' <<<"$out"; then
  pass "--help exits 0 and prints the full header without spilling into code"
else
  fail "--help should print the complete header and stop at the first code line (rc=$rc): $out"
fi

# 2. An explicit root that does not exist is a usage/env error (exit 2).
out="$(run "$TMP/does-not-exist" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'skills root does not exist' <<<"$out"; then
  pass "a missing explicit root exits 2 with a clear message"
else
  fail "a missing explicit root should exit 2 (rc=$rc): $out"
fi

# 2b. A missing explicit root is rejected even when ANOTHER root is valid.
#     Silently skipping it would omit a whole plugin subtree and report a
#     falsely low aggregate under an "OK" — the failure mode this guards.
mkdir -p "$TMP/valid-root/only-skill"
make_skill "$TMP/valid-root" only-skill "A fixture."
out="$(run "$TMP/valid-root" "$TMP/does-not-exist" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'skills root does not exist' <<<"$out"; then
  pass "a missing explicit root is rejected even when another root is valid"
else
  fail "a partially-missing explicit root list should exit 2, not silently skip (rc=$rc): $out"
fi

# 2c. The no-args resolution path still reports "no skills root found" rather
#     than the explicit-root error — the two branches stay distinct.
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/nope-root" bash "$SUT" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'no skills root found' <<<"$out"; then
  pass "an unresolvable no-args root exits 2 via the resolution-path message"
else
  fail "no-args resolution failure should exit 2 with 'no skills root found' (rc=$rc): $out"
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
if grep -q 'over 2 listing-eligible skill(s) across 2 root(s)' <<<"$out" && grep -q 'aggregate: 10 chars' <<<"$out"; then
  pass "multiple roots pool into one shared aggregate"
else
  fail "multiple roots should pool into one aggregate of 10 chars across 2 skills: $out"
fi

# 9. `disable-model-invocation: true` skills are excluded from the aggregate.
#    Their descriptions are never loaded into the model-visible listing
#    (https://code.claude.com/docs/en/skills — "Description not in context"),
#    so counting them would overstate the shared budget.
mkdir -p "$TMP/dmi-root"
make_skill "$TMP/dmi-root" eligible-skill "12345"
make_skill "$TMP/dmi-root" manual-skill "9999999999999999999999999" "" "true"
make_skill "$TMP/dmi-root" explicit-false-skill "67890" "" "false"
out="$(run "$TMP/dmi-root" 2>&1)"
if grep -q 'over 2 listing-eligible skill(s)' <<<"$out" && grep -q 'aggregate: 10 chars' <<<"$out"; then
  pass "disable-model-invocation: true skills are excluded; false is still counted"
else
  fail "expected 2 eligible skills totalling 10 chars (the dmi:true skill excluded): $out"
fi

# 10. A nonnumeric override is an environment error (exit 2), never a silent
#     awk coercion to zero (which fabricated a 0-char budget and a bogus
#     overflow WARN while still exiting 0) and never an undocumented exit 1.
#     Each case names the variable it expects to be blamed. The two ratio vars
#     are only consulted when CONTEXT_TOKENS selects the reconstruction branch,
#     so those cases set a valid CONTEXT_TOKENS alongside.
assert_env_error() {
  local var="$1" desc="$2"
  shift 2
  local out rc
  out="$(cd "$TMP" && env "$@" bash "$SUT" "$ROOT_A" 2>&1)"
  rc=$?
  if [[ $rc -eq 2 ]] && grep -q "$var must be a positive number" <<<"$out"; then
    pass "$desc is rejected as an environment error (exit 2)"
  else
    fail "$desc should exit 2 blaming $var (rc=$rc): $out"
  fi
}

assert_env_error CHECK_SKILL_LISTING_CONTEXT_TOKENS "a nonnumeric context-token count" \
  CHECK_SKILL_LISTING_CONTEXT_TOKENS=nope
assert_env_error CHECK_SKILL_LISTING_BUDGET_FRACTION "a nonnumeric budget fraction" \
  CHECK_SKILL_LISTING_CONTEXT_TOKENS=200000 CHECK_SKILL_LISTING_BUDGET_FRACTION=nope
assert_env_error CHECK_SKILL_LISTING_CHARS_PER_TOKEN "a nonnumeric chars-per-token ratio" \
  CHECK_SKILL_LISTING_CONTEXT_TOKENS=200000 CHECK_SKILL_LISTING_CHARS_PER_TOKEN=nope
assert_env_error CHECK_SKILL_LISTING_MAX_DESC_CHARS "a nonnumeric per-entry cap" \
  CHECK_SKILL_LISTING_MAX_DESC_CHARS=nope
assert_env_error CHECK_SKILL_LISTING_BUDGET_CHARS "a nonnumeric fixed budget" \
  CHECK_SKILL_LISTING_BUDGET_CHARS=nope
assert_env_error CHECK_SKILL_LISTING_BUDGET_CHARS "a zero fixed budget" \
  CHECK_SKILL_LISTING_BUDGET_CHARS=0

# 11. A valid decimal ratio/fraction is NOT rejected by the numeric guard —
#     the validation must accept the documented 0.01 default shape.
out="$(cd "$TMP" && CHECK_SKILL_LISTING_CONTEXT_TOKENS=1000000 CHECK_SKILL_LISTING_BUDGET_FRACTION=0.02 \
  CHECK_SKILL_LISTING_CHARS_PER_TOKEN=3.5 bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'reconstructed: 1000000 tokens x 3.5 chars/token x 0.02' <<<"$out"; then
  pass "decimal ratio and fraction overrides are accepted and reconstructed"
else
  fail "decimal overrides should reconstruct the budget and exit 0 (rc=$rc): $out"
fi

# 12. A supplied CHECK_SKILL_LISTING_BUDGET_CHARS is labelled an override, not
#     the "documented default" — the provenance the report promises to state.
out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=4000 bash "$SUT" "$ROOT_A" 2>&1)"
if grep -q 'budget:.*4000 chars (override (CHECK_SKILL_LISTING_BUDGET_CHARS))' <<<"$out"; then
  pass "a supplied fixed budget is labelled an override, not the documented default"
else
  fail "an overridden budget should not be labelled the documented default: $out"
fi

# 12b. With no override, the default IS labelled the documented default.
out="$(run "$ROOT_A" 2>&1)"
if grep -q 'budget:.*8000 chars (documented default' <<<"$out"; then
  pass "the unoverridden budget is labelled the documented default"
else
  fail "the default budget should carry the documented-default label: $out"
fi

# 13. The fixed budget takes precedence over the token reconstruction, per the
#     documented contract ("skips the token/fraction reconstruction"). The
#     reconstruction branch used to win and silently discard the fixed value,
#     which could flip the OK/WARN verdict.
out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=99999 CHECK_SKILL_LISTING_CONTEXT_TOKENS=200000 \
  bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'budget:.*99999 chars (override (CHECK_SKILL_LISTING_BUDGET_CHARS))' <<<"$out" &&
  grep -q 'takes precedence; ignoring CHECK_SKILL_LISTING_CONTEXT_TOKENS=200000' <<<"$out"; then
  pass "a fixed budget wins over the token reconstruction and says so"
else
  fail "the fixed budget should win and announce the ignored reconstruction input (rc=$rc): $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
