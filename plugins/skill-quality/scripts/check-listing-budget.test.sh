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
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_CONFIG 2>/dev/null || true
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

# 9b. The invocation-control flag is NORMALIZED before comparison. A bare
#     string compare against "true" silently re-counts a skill whose
#     description the harness excludes, because valid YAML can spell the same
#     boolean several ways. Covered: a trailing `# comment` (a YAML comment
#     requires preceding whitespace), surrounding whitespace, quoted forms,
#     and ASCII case variants. A `false` carrying a comment must still be
#     counted — that is what stops the normalization from over-matching.
mkdir -p "$TMP/dmi-norm-root"
make_skill "$TMP/dmi-norm-root" norm-inline-comment "12345" "" "true # manual-only"
make_skill "$TMP/dmi-norm-root" norm-quoted "12345" "" '"true"'
make_skill "$TMP/dmi-norm-root" norm-single-quoted "12345" "" "'true'"
make_skill "$TMP/dmi-norm-root" norm-quoted-comment "12345" "" "'true'  # manual"
make_skill "$TMP/dmi-norm-root" norm-upper "12345" "" "TRUE"
make_skill "$TMP/dmi-norm-root" norm-title "12345" "" "True"
make_skill "$TMP/dmi-norm-root" norm-trailing-space "12345" "" "true   "
make_skill "$TMP/dmi-norm-root" norm-false-comment "12345" "" "false # still listed"
make_skill "$TMP/dmi-norm-root" norm-eligible "67890"
out="$(run "$TMP/dmi-norm-root" 2>&1)"
if grep -q 'over 2 listing-eligible skill(s)' <<<"$out" && grep -q 'aggregate: 10 chars' <<<"$out"; then
  pass "the invocation-control boolean is normalized (comment, quotes, case, whitespace)"
else
  fail "only norm-false-comment and norm-eligible should count (2 skills, 10 chars): $out"
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

# 14. A zero-padded integer override means what it reads as. `^[0-9]+$` accepts
#     it, but bash arithmetic and `printf %d` then read it as OCTAL: `08` was a
#     hard "invalid octal number" that rendered the budget as 0 and still
#     reported OK, and `0123` silently became 83. Each case asserts the DECIMAL
#     reading and the absence of the octal diagnostic.
out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=0123 bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -qE 'budget:.*(^|[^0-9])123 chars \(override' <<<"$out" && ! grep -q 'octal' <<<"$out"; then
  pass "a zero-padded fixed budget is read as decimal 123, not octal 83"
else
  fail "CHECK_SKILL_LISTING_BUDGET_CHARS=0123 should report a 123-char budget (rc=$rc): $out"
fi

# 14b. `08` is not a valid octal literal at all — the case that degraded the
#      budget to 0 and reported a bogus "OK" while exiting 0.
out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=08 bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -qE 'budget:.*(^|[^0-9])8 chars \(override' <<<"$out" &&
  ! grep -q 'octal' <<<"$out" && ! grep -qE 'budget:.*(^|[^0-9])0 chars' <<<"$out"; then
  pass "a zero-padded 08 fixed budget is read as decimal 8, not an octal error"
else
  fail "CHECK_SKILL_LISTING_BUDGET_CHARS=08 should report an 8-char budget (rc=$rc): $out"
fi

# 14c. The per-entry cap takes the same normalization — a zero-padded `010` cap
#      truncated entries at 8 chars instead of the requested 10.
mkdir -p "$TMP/pad-cap-root"
make_skill "$TMP/pad-cap-root" pad-cap-skill "123456789012345"
out="$(cd "$TMP" && CHECK_SKILL_LISTING_MAX_DESC_CHARS=010 bash "$SUT" "$TMP/pad-cap-root" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'aggregate: 10 chars' <<<"$out"; then
  pass "a zero-padded per-entry cap truncates at decimal 10, not octal 8"
else
  fail "CHECK_SKILL_LISTING_MAX_DESC_CHARS=010 should cap the entry at 10 chars (rc=$rc): $out"
fi

# 14d. The decimal fraction default must keep working — it legitimately starts
#      with a zero, so the normalization must not reach the ratio overrides.
out="$(cd "$TMP" && CHECK_SKILL_LISTING_CONTEXT_TOKENS=0200000 CHECK_SKILL_LISTING_BUDGET_FRACTION=0.01 \
  bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'reconstructed: 200000 tokens x 4 chars/token x 0.01' <<<"$out"; then
  pass "a zero-padded token count normalizes while the 0.01 fraction is left intact"
else
  fail "a padded token count should reconstruct from decimal 200000 with fraction 0.01 (rc=$rc): $out"
fi

# 15. A trailing YAML comment on `description` / `when_to_use` is NOT part of
#     the value a YAML reader delivers, so it must not be measured. It also
#     hides the surrounding quotes from `strip_quotes`, which used to leave the
#     quoting in the count too: this fixture measured 52 chars instead of 15.
#     `make_skill` always emits a quoted scalar, so the raw file is written here.
mkdir -p "$TMP/yaml-comment-root/commented"
{
  printf -- '---\n'
  printf 'name: commented\n'
  printf 'description: "12345" # maintainer note\n'
  printf 'when_to_use: "1234567" # another note\n'
  printf -- '---\n\n## Purpose\n\nFixture.\n'
} >"$TMP/yaml-comment-root/commented/SKILL.md"
out="$(run "$TMP/yaml-comment-root" 2>&1)"
if grep -q 'aggregate: 15 chars' <<<"$out"; then
  pass "a trailing YAML comment is excluded from the measured description"
else
  fail "the commented fixture should measure 15 chars (5 + 3 joiner + 7): $out"
fi

# 15b. An unquoted (plain) scalar ends at the first whitespace-preceded `#`,
#      which is what a YAML reader does — and a `#` with no preceding
#      whitespace is ordinary content that must survive.
mkdir -p "$TMP/yaml-plain-root/plain"
{
  printf -- '---\n'
  printf 'name: plain\n'
  printf 'description: 12345 # trailing note\n'
  printf 'when_to_use: tag#7 stays\n'
  printf -- '---\n\n## Purpose\n\nFixture.\n'
} >"$TMP/yaml-plain-root/plain/SKILL.md"
out="$(run "$TMP/yaml-plain-root" 2>&1)"
if grep -q 'aggregate: 19 chars' <<<"$out"; then
  pass "a plain scalar drops its trailing comment but keeps a non-comment #"
else
  fail "the plain fixture should measure 19 chars (5 + 3 joiner + 11): $out"
fi

# 15c. A `#` inside a BLOCK scalar is content, not a comment — a markdown
#      heading in a folded description must survive intact.
mkdir -p "$TMP/yaml-block-root/blocky"
{
  printf -- '---\n'
  printf 'name: blocky\n'
  printf 'description: >\n'
  printf '  abc # def\n'
  printf -- '---\n\n## Purpose\n\nFixture.\n'
} >"$TMP/yaml-block-root/blocky/SKILL.md"
out="$(run "$TMP/yaml-block-root" 2>&1)"
if grep -q 'aggregate: 9 chars' <<<"$out"; then
  pass "a # inside a block scalar is content and is still measured"
else
  fail "the block fixture should measure all 9 chars of 'abc # def': $out"
fi

# ===================== single-pass port guards (#2216) ======================
#
# The measurement is one awk pass rather than ~11 forked subshells and 5 process
# execs per SKILL.md. Corpus equivalence over the repo's ~200 files (proved by
# diffing both implementations' per-file contribution rows) is NOT parser
# equivalence, so the frontmatter shapes most likely to diverge get fixtures.

# 16. LITERAL block scalar (`|`) joins its lines with NEWLINES, and the trailing
#     blank line before the closing fence must not add one — the pre-port
#     pipeline got that for free from command substitution stripping trailing
#     newlines, and the port has to reproduce it deliberately.
mkdir -p "$TMP/yaml-literal-root/lit"
{
  printf -- '---\n'
  printf 'name: lit\n'
  printf 'description: |\n'
  printf '  abc\n'
  printf '  de\n'
  printf '\n'
  printf -- '---\n\n## Purpose\n\nFixture.\n'
} >"$TMP/yaml-literal-root/lit/SKILL.md"
out="$(run "$TMP/yaml-literal-root" 2>&1)"
if grep -q 'aggregate: 6 chars' <<<"$out"; then
  pass "a literal block scalar joins with newlines and drops the trailing blank"
else
  fail "the literal fixture should measure 6 chars ('abc' + LF + 'de'): $out"
fi

# 17. A SINGLE-quoted scalar escapes one quote by doubling it, so the doubled
#     pair is content and the scalar does not end there. Getting this wrong
#     truncates the value at the first inner quote and undercounts silently.
mkdir -p "$TMP/yaml-sq-root/sq"
{
  printf -- '---\n'
  printf 'name: sq\n'
  printf "description: 'it''s ok' # note\n"
  printf -- '---\n\n## Purpose\n\nFixture.\n'
} >"$TMP/yaml-sq-root/sq/SKILL.md"
out="$(run "$TMP/yaml-sq-root" 2>&1)"
if grep -q 'aggregate: 8 chars' <<<"$out"; then
  pass "a doubled single quote is content; the trailing comment is still cut"
else
  fail "the single-quote fixture should measure 8 chars: $out"
fi

# 18. LENGTH SEMANTICS, asserted as an EQUIVALENCE rather than a hardcoded
#     number. The pre-port script measured with bash `${#var}`; the port
#     measures with awk `length()`. Both are locale-dependent and they can
#     disagree when awk counts bytes while the shell counts characters (mawk
#     ignores the locale; gawk does not). A fixed expected number would encode
#     ONE environment's answer and fail elsewhere for the wrong reason — this
#     compares the script's own output against the measurement primitive the
#     OLD implementation used, in the SAME shell, so a divergence is reported
#     as exactly what it is.
mkdir -p "$TMP/yaml-utf8-root/utf8"
UTF8_DESC='a—b…c'
{
  printf -- '---\n'
  printf 'name: utf8\n'
  printf 'description: "%s"\n' "$UTF8_DESC"
  printf -- '---\n\n## Purpose\n\nFixture.\n'
} >"$TMP/yaml-utf8-root/utf8/SKILL.md"
out="$(run "$TMP/yaml-utf8-root" 2>&1)"
if grep -q "aggregate: ${#UTF8_DESC} chars" <<<"$out"; then
  pass "multibyte description measures the same as the shell's own \${#var} (${#UTF8_DESC} chars)"
else
  fail "awk length() and bash \${#var} disagree on a multibyte value (expected ${#UTF8_DESC}): $out"
fi

# 19. WALL CLOCK over a ~200-file corpus — the regression this port exists to
#     prevent. The pooled run took 289s on Windows and was killed at the 180s
#     foreground limit with zero output; the single pass returns in low
#     single-digit seconds. The bound is deliberately VERY loose (30s for 200
#     files against a sub-second target): this runs in required CI, and a tight
#     timing assertion is a flaky gate, which is worse than the defect it
#     guards. It fails only on a return to per-file process spawning, which is
#     two orders of magnitude away.
mkdir -p "$TMP/perf-root"
i=0
while ((i < 200)); do
  mkdir -p "$TMP/perf-root/skill-$i"
  {
    printf -- '---\n'
    printf 'name: skill-%d\n' "$i"
    printf 'description: "a description long enough to be representative of a real listing entry"\n'
    printf 'when_to_use: "when the fixture needs a second measured field"\n'
    printf -- '---\n\n## Purpose\n\nFixture.\n'
  } >"$TMP/perf-root/skill-$i/SKILL.md"
  i=$((i + 1))
done
perf_start=$(date +%s)
out="$(run "$TMP/perf-root" 2>&1)"
perf_elapsed=$(($(date +%s) - perf_start))
if grep -q '200 listing-eligible skill' <<<"$out" && ((perf_elapsed < 30)); then
  pass "200-file corpus measured in ${perf_elapsed}s (bound: 30s)"
else
  fail "200-file corpus took ${perf_elapsed}s or miscounted (bound 30s): $out"
fi

# 20. Non-git plugin-cache tree: explicit root still reports.
#     Marketplace installs are plain dirs; an explicit skills root must not
#     abort with "not in a git repo" just because cwd has no .git.
CACHE_TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$CACHE_TMP"' EXIT
CACHE_SKILLS="$CACHE_TMP/marketplace/some-plugin/1.0.0/skills"
make_skill "$CACHE_SKILLS" cache-skill "A cache-install fixture description."
out="$(
  cd "$CACHE_TMP" &&
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_PREFIX \
      bash "$SUT" "$CACHE_SKILLS" 2>&1
)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'CHECK-LISTING-BUDGET: OK' <<<"$out" &&
  ! grep -q 'Error: not in a git repo' <<<"$out"; then
  pass "non-git plugin-cache tree: listing-budget reports over an explicit root"
else
  fail "non-git explicit root should report OK without git (rc=$rc): $out"
fi

# 20b. Outside git with no args and no override is still an environment error.
out="$(
  cd "$CACHE_TMP" &&
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_PREFIX \
      -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR \
      bash "$SUT" 2>&1
)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'no skills root set' <<<"$out"; then
  pass "outside git with no args/override still exits 2 naming the missing root"
else
  fail "outside git with no args should exit 2 (rc=$rc): $out"
fi

# 20c. CHECK_SKILL_SKILLS_ROOT from a non-git cwd still resolves (no-args form).
out="$(
  cd "$CACHE_TMP" &&
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_PREFIX \
      CHECK_SKILL_SKILLS_ROOT="$CACHE_SKILLS" \
      bash "$SUT" 2>&1
)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'CHECK-LISTING-BUDGET: OK' <<<"$out"; then
  pass "non-git no-args form honors CHECK_SKILL_SKILLS_ROOT"
else
  fail "non-git CHECK_SKILL_SKILLS_ROOT should report OK (rc=$rc): $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
