#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-skill-count-claims.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TMP="" CLEAN=""

fixture_tree::build TMP --sut "$SUT_SRC" --plugins
SUT="$TMP/scripts/check-skill-count-claims.sh"
EXEMPTIONS="$TMP/scripts/skill-count-claim-exemptions.txt"
: >"$EXEMPTIONS"

make_skill() {
  local plugin="$1" skill="$2"
  mkdir -p "$TMP/plugins/$plugin/skills/$skill"
  printf -- '---\nname: %s\ndescription: "fixture"\n---\n' "$skill" >"$TMP/plugins/$plugin/skills/$skill/SKILL.md"
}

readme() {
  local plugin="$1"
  shift
  printf '%s\n' "$@" >"$TMP/plugins/$plugin/README.md"
}

run() { (cd "$TMP" && bash "$SUT" "$@" 2>&1); }
run_rc() {
  (cd "$TMP" && bash "$SUT" "$@" >/dev/null 2>&1)
  printf '%d' "$?"
}

make_skill alpha one
make_skill alpha two
make_skill alpha three
readme alpha \
  'A plugin bundling three skills for one job.' \
  'Three skills, one concern: fixtures.' \
  'Only the first has prerequisites; the other two skills are zero-config.'

make_skill beta a
make_skill beta b
make_skill beta c
make_skill beta d
readme beta \
  'It ships two skills:' \
  'Two skills, one concern: being wrong.'
mkdir -p "$TMP/plugins/beta/.claude-plugin"
printf '{\n  "description": "Toolkit of two skills: a, b."\n}\n' \
  >"$TMP/plugins/beta/.claude-plugin/plugin.json"

make_skill gamma a
make_skill gamma b
readme gamma \
  'Two skills, one concern: not over-flagging.' \
  'The Skill tool takes one skill per call; a step needing two skills is two calls.' \
  'Nine skills moved into three new plugins in an earlier release.' \
  'Run the gate over one skill at a time.' \
  'One skill per discipline is the rule of thumb.' \
  'The two skills this must not be confused with live elsewhere.' \
  'Emphasize deliberate practice: small tasks focused on 1-2 skills at a time.'

make_skill delta a
make_skill delta b
make_skill delta c
readme delta 'Three skills, one concern: history.'
printf '%s\n' '- The plugin now bundles two skills.' \
  >"$TMP/plugins/delta/CHANGELOG.md"

make_skill epsilon a
make_skill epsilon b
readme epsilon 'A plugin bundling 5 skills for one job.'

mkdir -p "$TMP/plugins/zeta"
readme zeta \
  'One skill, one job: being deleted.' \
  'Only the observer needs setup; the other three skills are zero-config.'

make_skill eta a
make_skill eta b
readme eta \
  'A Claude Code plugin for evaluating wrapped prose. Two' \
  'skills, one concern: straddling a line break.'

make_skill theta a
make_skill theta b
readme theta '## IT SHIPS THREE SKILLS' 'Body text.'

make_skill iota a
make_skill iota b
readme iota \
  '# iota' \
  '' \
  'Two skills, one concern: not being counted twice.'

make_skill kappa a
make_skill kappa b
readme kappa \
  'A Claude Code plugin for overlapping grammars. It ships' \
  'two skills, one concern: matching two forms at once.'

out="$(run)"

if [[ "$(grep -c '^ok .*alpha' <<<"$out")" -eq 3 ]]; then
  ok "all three correct alpha claims verify"
else
  fail "expected 3 ok rows for alpha: $out"
fi

if grep -q 'alpha .*two -> two (total minus one)' <<<"$out"; then
  ok "other-N idiom resolves to total minus one"
else
  fail "other-N idiom should compare against total-1: $out"
fi

if [[ "$(grep -c '^MISMATCH.*beta' <<<"$out")" -eq 3 ]]; then
  ok "stale count flags in README prose and plugin manifest"
else
  fail "expected 3 beta mismatches (2 README, 1 manifest): $out"
fi

if ! grep -q 'gamma' <<<"$(grep '^MISMATCH' <<<"$out")"; then
  ok "non-claim prose does not flag"
else
  fail "gamma prose should not produce any mismatch: $out"
fi

if ! grep -q 'the two skills this must not' <<<"$out"; then
  ok "definite-article reference is not treated as a claim"
else
  fail "'the two skills' should not be a recognized claim form: $out"
fi

if ! grep -q 'CHANGELOG' <<<"$out"; then
  ok "CHANGELOG.md is not scanned"
else
  fail "CHANGELOG.md must be out of scope: $out"
fi

if grep -qE 'MISMATCH.*epsilon .*5 -> 2$' <<<"$out"; then
  ok "digit-form claim flags and its remediation stays numeric"
else
  fail "epsilon should flag as 5 -> 2 in digits: $out"
fi

if grep -qE 'MISMATCH.*zeta/README.md:1 .*one -> zero' <<<"$out"; then
  ok "plugin with no skills/ directory is scanned as zero, not skipped"
else
  fail "zeta should flag as one -> zero: $out"
fi

if grep -qE '^ok .*eta/README.md:1 ' <<<"$out"; then
  ok "wrapped claim is found and anchored to its opening line"
else
  fail "eta's wrapped claim should verify at line 1: $out"
fi

if grep -qE 'MISMATCH.*theta/README.md:1 .*three -> two' <<<"$out"; then
  ok "all-caps claim is not dropped by the prefilter"
else
  fail "theta's SKILLS claim should flag as three -> two: $out"
fi

if [[ "$(grep -c 'iota/README.md' <<<"$out")" -eq 1 ]]; then
  ok "a claim adjacent to a blank line is reported exactly once"
else
  fail "iota's claim should appear exactly once: $out"
fi

if [[ "$(grep -c 'kappa/README.md' <<<"$out")" -eq 1 ]]; then
  ok "a claim satisfying two forms across a wrap is reported once"
else
  fail "kappa's claim should appear exactly once: $out"
fi

out_check="$(run --check)"
if grep -q 'plugin zeta has zero' <<<"$out_check" &&
  grep -q 'the number should be zero' <<<"$out_check"; then
  ok "zero-skill minus-one FAIL text agrees with itself"
else
  fail "zeta's minus-one FAIL should say 'has zero' and 'should be zero': $out_check"
fi

rc="$(run_rc --check)"
if [[ "$rc" -eq 1 ]]; then
  ok "--check fails on a stale count"
else
  fail "--check should exit 1 with mismatches present (rc=$rc)"
fi

out="$(run --check)"
if grep -q 'plugins/beta/README.md' <<<"$out" && grep -q 'Change it to "four"' <<<"$out"; then
  ok "failure names the site and the corrected spelled number"
else
  fail "failure should name site and corrected word: $out"
fi

printf 'plugins/beta/README.md|It ships two skills\n' >"$EXEMPTIONS"
out="$(run)"
if grep -q '^exempt .*beta/README.md' <<<"$out" &&
  [[ "$(grep -c '^MISMATCH.*beta' <<<"$out")" -eq 2 ]]; then
  ok "exemption suppresses exactly its own line"
else
  fail "exemption should suppress one beta line only: $out"
fi

printf 'plugins/beta/README.md|a sentence that is not there\n' >"$EXEMPTIONS"
out="$(run --check)"
if grep -q 'no longer produces a mismatch' <<<"$out"; then
  ok "stale exemption fails --check"
else
  fail "stale exemption should fail: $out"
fi
if grep -q "STALE BASELINE: .*: 'plugins/beta/README.md|a sentence that is not there'" <<<"$out"; then
  ok "the stale exemption carries the shared STALE BASELINE prefix"
else
  fail "expected the shared STALE BASELINE diagnostic: $out"
fi

printf 'plugins/beta/README.md|It ships two skills' >"$EXEMPTIONS"
out="$(run --check)"
if ! grep -q 'STALE BASELINE' <<<"$out"; then
  ok "a final exemption row with no trailing newline is loaded"
else
  fail "unterminated final exemption row was dropped: $out"
fi

printf 'plugins/omega/README.md|anything\n' >"$EXEMPTIONS"
out="$(run --check)"
if grep -q 'no longer exists' <<<"$out"; then
  ok "exemption for a missing file fails with that reason"
else
  fail "missing-file exemption should fail: $out"
fi

printf 'no-separator-here\n' >"$EXEMPTIONS"
rc="$(run_rc --check)"
if [[ "$rc" -eq 2 ]]; then
  ok "malformed exemption exits 2"
else
  fail "malformed exemption should exit 2 (rc=$rc)"
fi

: >"$EXEMPTIONS"
rm -rf "$TMP/plugins/beta" "$TMP/plugins/epsilon" \
  "$TMP/plugins/zeta" "$TMP/plugins/theta"
out="$(run --check)"
rc="$(run_rc --check)"
if [[ "$rc" -eq 0 ]] && grep -qE 'All [0-9]+ skill-count claim' <<<"$out"; then
  ok "clean tree passes and reports its claim count"
else
  fail "clean tree should pass with a count (rc=$rc): $out"
fi

fixture_tree::build CLEAN --sut "$SUT_SRC" --plugins
mkdir -p "$CLEAN/plugins/solo/skills/only"
printf -- '---\nname: only\n---\n' >"$CLEAN/plugins/solo/skills/only/SKILL.md"
printf 'No counts here.\n' >"$CLEAN/plugins/solo/README.md"
out="$( (cd "$CLEAN" && bash "$CLEAN/scripts/check-skill-count-claims.sh" 2>&1))"
if grep -q 'No skill-count claims found' <<<"$out"; then
  ok "a tree with no claims says so"
else
  fail "no-claims tree should say so: $out"
fi
rm -rf "$CLEAN"

rc="$(run_rc --bogus)"
if [[ "$rc" -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

test_harness::report
