#!/usr/bin/env bash
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
unset SLASH_COMMAND_TOOL_CHAR_BUDGET CLAUDE_PROJECT_DIR CHECK_SKILL_SKILLS_ROOT \
  CHECK_SKILL_LISTING_BUDGET_CHARS CHECK_SKILL_LISTING_CONTEXT_TOKENS \
  CHECK_SKILL_LISTING_BUDGET_FRACTION CHECK_SKILL_LISTING_CHARS_PER_TOKEN \
  CHECK_SKILL_LISTING_MAX_DESC_CHARS 2>/dev/null || true
export HOME="$TMP/home"
export CLAUDE_CONFIG_DIR="$TMP/home/.claude"
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

out="$(run --help 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'Exit 0 always (report-only)' <<<"$out" &&
  ! grep -q 'set -uo pipefail' <<<"$out"; then
  pass "--help exits 0 and prints the full header without spilling into code"
else
  fail "--help should print the complete header and stop at the first code line (rc=$rc): $out"
fi

out="$(run "$TMP/does-not-exist" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'skills root does not exist' <<<"$out"; then
  pass "a missing explicit root exits 2 with a clear message"
else
  fail "a missing explicit root should exit 2 (rc=$rc): $out"
fi

make_skill "$TMP/valid-root" only-skill "A fixture."
out="$(run "$TMP/valid-root" "$TMP/does-not-exist" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'skills root does not exist' <<<"$out"; then
  pass "a missing explicit root is rejected even when another root is valid"
else
  fail "a partially-missing explicit root list should exit 2, not silently skip (rc=$rc): $out"
fi

out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/nope-root" bash "$SUT" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'no skills root found' <<<"$out"; then
  pass "an unresolvable no-args root exits 2 via the resolution-path message"
else
  fail "no-args resolution failure should exit 2 with 'no skills root found' (rc=$rc): $out"
fi

mkdir -p "$TMP/empty-root"
out="$(run "$TMP/empty-root" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q '0 skills, nothing to report' <<<"$out"; then
  pass "empty root reports zero skills and exits 0"
else
  fail "empty root should report zero and exit 0 (rc=$rc): $out"
fi

make_skill "$ROOT_A" small-one "A small fixture skill."
make_skill "$ROOT_A" small-two "Another small fixture skill."
out="$(run "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'CHECK-LISTING-BUDGET: OK' <<<"$out"; then
  pass "small aggregate under the default budget reports OK"
else
  fail "small aggregate should report OK (rc=$rc): $out"
fi

out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=10 bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: aggregate exceeds the budget' <<<"$out" && grep -q 'CHECK-LISTING-BUDGET: WARN' <<<"$out"; then
  pass "a forced tiny budget trips the WARN path but still exits 0 (advisory only)"
else
  fail "forced tiny budget should WARN and still exit 0 (rc=$rc): $out"
fi

desc_40='1234567890123456789012345678901234567890'
wtu_10='1234567890'
make_skill "$TMP/joiner-root" joiner-skill "$desc_40" "$wtu_10"
out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=50 bash "$SUT" "$TMP/joiner-root" 2>&1)"
if grep -q 'aggregate: 53 chars' <<<"$out" && grep -q 'WARN: aggregate exceeds the budget by 3 chars' <<<"$out"; then
  pass "the 3-char description/when_to_use joiner is counted in the aggregate"
else
  fail "aggregate should count the 3-char joiner (expected 53 chars, WARN by 3): $out"
fi

long_desc="$(printf 'x%.0s' {1..200})"
make_skill "$TMP/cap-root" cap-skill "$long_desc"
out="$(cd "$TMP" && CHECK_SKILL_LISTING_MAX_DESC_CHARS=50 CHECK_SKILL_LISTING_BUDGET_CHARS=1000 bash "$SUT" "$TMP/cap-root" 2>&1)"
if grep -q 'aggregate: 50 chars' <<<"$out"; then
  pass "an oversized entry is capped at CHECK_SKILL_LISTING_MAX_DESC_CHARS before summing"
else
  fail "oversized entry should cap at 50 chars, not count all 200 (expected 'aggregate: 50 chars'): $out"
fi

make_skill "$TMP/root-x" x-skill "12345"
make_skill "$TMP/root-y" y-skill "67890"
out="$(run "$TMP/root-x" "$TMP/root-y" 2>&1)"
if grep -q 'over 2 listing-eligible skill(s) across 2 root(s)' <<<"$out" && grep -q 'aggregate: 10 chars' <<<"$out"; then
  pass "multiple roots pool into one shared aggregate"
else
  fail "multiple roots should pool into one aggregate of 10 chars across 2 skills: $out"
fi

make_skill "$TMP/dmi-root" eligible-skill "12345"
make_skill "$TMP/dmi-root" manual-skill "9999999999999999999999999" "" "true"
make_skill "$TMP/dmi-root" explicit-false-skill "67890" "" "false"
out="$(run "$TMP/dmi-root" 2>&1)"
if grep -q 'over 2 listing-eligible skill(s)' <<<"$out" && grep -q 'aggregate: 10 chars' <<<"$out"; then
  pass "disable-model-invocation: true skills are excluded; false is still counted"
else
  fail "expected 2 eligible skills totaling 10 chars (the dmi:true skill excluded): $out"
fi

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

i=0
for spelling in yes YES On on 1; do
  i=$((i + 1))
  make_skill "$TMP/dmi-spell-root" "spell-true-$i" "9999999999999999999999999" "" "$spelling"
done
i=0
for spelling in no OFF off 0; do
  i=$((i + 1))
  make_skill "$TMP/dmi-spell-root" "spell-false-$i" "12345" "" "$spelling"
done
out="$(run "$TMP/dmi-spell-root" 2>&1)"
if grep -q 'over 4 listing-eligible skill(s)' <<<"$out" && grep -q 'aggregate: 20 chars' <<<"$out"; then
  pass "every documented boolean spelling of disable-model-invocation is honored"
else
  fail "only the 4 false spellings should count (4 skills, 20 chars): $out"
fi

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

out="$(cd "$TMP" && CHECK_SKILL_LISTING_CONTEXT_TOKENS=1000000 CHECK_SKILL_LISTING_BUDGET_FRACTION=0.02 \
  CHECK_SKILL_LISTING_CHARS_PER_TOKEN=3.5 bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'reconstructed: 1000000 tokens x 3.5 chars/token x 0.02' <<<"$out"; then
  pass "decimal ratio and fraction overrides are accepted and reconstructed"
else
  fail "decimal overrides should reconstruct the budget and exit 0 (rc=$rc): $out"
fi

out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=4000 bash "$SUT" "$ROOT_A" 2>&1)"
if grep -q 'budget:.*4000 chars (override (CHECK_SKILL_LISTING_BUDGET_CHARS))' <<<"$out"; then
  pass "a supplied fixed budget is labeled an override, not the documented default"
else
  fail "an overridden budget should not be labeled the documented default: $out"
fi

out="$(run "$ROOT_A" 2>&1)"
if grep -q 'budget:.*8000 chars (documented default' <<<"$out"; then
  pass "the unoverridden budget is labeled the documented default"
else
  fail "the default budget should carry the documented-default label: $out"
fi

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

out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=0123 bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -qE 'budget:.*(^|[^0-9])123 chars \(override' <<<"$out" && ! grep -q 'octal' <<<"$out"; then
  pass "a zero-padded fixed budget is read as decimal 123, not octal 83"
else
  fail "CHECK_SKILL_LISTING_BUDGET_CHARS=0123 should report a 123-char budget (rc=$rc): $out"
fi

out="$(cd "$TMP" && CHECK_SKILL_LISTING_BUDGET_CHARS=08 bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -qE 'budget:.*(^|[^0-9])8 chars \(override' <<<"$out" &&
  ! grep -q 'octal' <<<"$out" && ! grep -qE 'budget:.*(^|[^0-9])0 chars' <<<"$out"; then
  pass "a zero-padded 08 fixed budget is read as decimal 8, not an octal error"
else
  fail "CHECK_SKILL_LISTING_BUDGET_CHARS=08 should report an 8-char budget (rc=$rc): $out"
fi

make_skill "$TMP/pad-cap-root" pad-cap-skill "123456789012345"
out="$(cd "$TMP" && CHECK_SKILL_LISTING_MAX_DESC_CHARS=010 bash "$SUT" "$TMP/pad-cap-root" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'aggregate: 10 chars' <<<"$out"; then
  pass "a zero-padded per-entry cap truncates at decimal 10, not octal 8"
else
  fail "CHECK_SKILL_LISTING_MAX_DESC_CHARS=010 should cap the entry at 10 chars (rc=$rc): $out"
fi

out="$(cd "$TMP" && CHECK_SKILL_LISTING_CONTEXT_TOKENS=0200000 CHECK_SKILL_LISTING_BUDGET_FRACTION=0.01 \
  bash "$SUT" "$ROOT_A" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'reconstructed: 200000 tokens x 4 chars/token x 0.01' <<<"$out"; then
  pass "a zero-padded token count normalizes while the 0.01 fraction is left intact"
else
  fail "a padded token count should reconstruct from decimal 200000 with fraction 0.01 (rc=$rc): $out"
fi

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

BIG_ROOT="$TMP/big/skills"
long_desc="$(printf '%1600s' '' | tr ' ' 'x')"
for i in $(seq 1 27); do
  make_skill "$BIG_ROOT" "big-$i" "$long_desc"
done
write_fraction() {
  mkdir -p "$(dirname "$1")"
  printf '{"skillListingBudgetFraction": %s}\n' "$2" >"$1"
}
run_cfg() {
  local proj="$1" cfg="$2"
  shift 2
  (cd "$TMP" && CLAUDE_PROJECT_DIR="$proj" CLAUDE_CONFIG_DIR="$cfg" bash "$SUT" "$@")
}

CFG21="$TMP/s21/config"
write_fraction "$CFG21/settings.json" 0.05
out="$(run_cfg "$TMP/s21/project" "$CFG21" --from-settings "$BIG_ROOT" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'fraction:  0\.05 (settings:.*/s21/config/settings\.json)' <<<"$out" &&
  grep -qF 'budget:    40000 chars (reconstructed: 200000 tokens x 4 chars/token x 0.05): WARN, over by 1472 chars' <<<"$out" &&
  grep -qF 'budget:    200000 chars (reconstructed: 1000000 tokens x 4 chars/token x 0.05): OK' <<<"$out" &&
  grep -q 'over 1 of 2 budgets at the configured fraction 0.05' <<<"$out"; then
  pass "--from-settings reads a user-scope fraction and reports a verdict per window"
else
  fail "--from-settings should report 40000 (WARN) and 200000 (OK) from the user settings file (rc=$rc): $out"
fi

P22="$TMP/s22/project"
CFG22="$TMP/s22/config"
write_fraction "$P22/.claude/settings.local.json" 0.03
write_fraction "$P22/.claude/settings.json" 0.02
write_fraction "$CFG22/settings.json" 0.05
out="$(run_cfg "$P22" "$CFG22" --from-settings "$BIG_ROOT" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'fraction:  0\.03 (settings:.*/s22/project/\.claude/settings\.local\.json)' <<<"$out" &&
  grep -qF 'budget:    24000 chars' <<<"$out" &&
  grep -qF 'budget:    120000 chars' <<<"$out"; then
  pass "--from-settings takes the project-local fraction over project and user"
else
  fail "project settings.local.json should win (0.03 -> 24000/120000) (rc=$rc): $out"
fi
rm "$P22/.claude/settings.local.json"
out="$(run_cfg "$P22" "$CFG22" --from-settings "$BIG_ROOT" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'fraction:  0\.02 (settings:.*/s22/project/\.claude/settings\.json)' <<<"$out" &&
  grep -qF 'budget:    16000 chars' <<<"$out" &&
  grep -qF 'budget:    80000 chars' <<<"$out"; then
  pass "--from-settings takes the shared project fraction over the user one"
else
  fail "project settings.json should beat user settings (0.02 -> 16000/80000) (rc=$rc): $out"
fi

out="$(cd "$TMP" && CLAUDE_PROJECT_DIR="$P22" CLAUDE_CONFIG_DIR="$CFG22" \
  SLASH_COMMAND_TOOL_CHAR_BUDGET=12345 bash "$SUT" --from-settings "$BIG_ROOT" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -qF 'budget:    12345 chars (env:SLASH_COMMAND_TOOL_CHAR_BUDGET)' <<<"$out" &&
  [[ "$(grep -c 'budget:    ' <<<"$out")" -eq 1 ]]; then
  pass "SLASH_COMMAND_TOOL_CHAR_BUDGET fixes the budget over the settings fraction"
else
  fail "SLASH_COMMAND_TOOL_CHAR_BUDGET=12345 should be the only budget row (rc=$rc): $out"
fi

out="$(cd "$TMP" && CLAUDE_PROJECT_DIR="$P22" CLAUDE_CONFIG_DIR="$CFG22" \
  SLASH_COMMAND_TOOL_CHAR_BUDGET=12345 bash "$SUT" "$BIG_ROOT" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -qF 'budget:    8000 chars (documented default (SLASH_COMMAND_TOOL_CHAR_BUDGET fallback))' <<<"$out" &&
  grep -q 'over budget by 33472 at the documented default budget' <<<"$out" &&
  ! grep -q 'configured' <<<"$out" &&
  ! grep -q 'fraction:' <<<"$out"; then
  pass "default-consumer mode ignores settings and env, and never says configured"
else
  fail "no flag should report the 8000 default, over by 33472, without 'configured' (rc=$rc): $out"
fi

out="$(CHECK_SKILL_LISTING_BUDGET_FRACTION=0.05 run "$BIG_ROOT" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -qF 'fraction:  0.05 (override (CHECK_SKILL_LISTING_BUDGET_FRACTION))' <<<"$out" &&
  grep -qF 'budget:    40000 chars' <<<"$out" &&
  grep -qF 'budget:    200000 chars' <<<"$out" &&
  ! grep -qF 'budget:    8000 chars' <<<"$out"; then
  pass "a fraction override without a window reports the 200k/1M band"
else
  fail "CHECK_SKILL_LISTING_BUDGET_FRACTION alone should give 40000/200000 (rc=$rc): $out"
fi

out="$(run_cfg "$TMP/s26/project" "$TMP/s26/config" --from-settings "$BIG_ROOT" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'fraction:  0.01 (documented default' <<<"$out" &&
  grep -qF 'budget:    8000 chars' <<<"$out" &&
  grep -qF 'budget:    40000 chars' <<<"$out" &&
  grep -q 'over 2 of 2 budgets at the documented default fraction 0.01' <<<"$out" &&
  ! grep -q 'configured' <<<"$out"; then
  pass "--from-settings with no settings reports the documented-default band"
else
  fail "no settings file should give the 0.01 band 8000/40000 labeled default (rc=$rc): $out"
fi

CFG27="$TMP/s27/config"
mkdir -p "$CFG27"
printf '{"skillListingBudgetFraction": \n' >"$CFG27/settings.json"
out="$(run_cfg "$TMP/s27/project" "$CFG27" --from-settings "$BIG_ROOT" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'could not parse settings JSON' <<<"$out"; then
  pass "malformed settings JSON exits 2"
else
  fail "malformed settings JSON should exit 2 (rc=$rc): $out"
fi

out="$(run --bogus 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'unknown option: --bogus' <<<"$out"; then
  pass "an unknown option exits 2 naming it"
else
  fail "an unknown option should exit 2 naming it (rc=$rc): $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
