#!/usr/bin/env bash
# Black-box contract test for check-skill-count-claims.sh.
#
# Self-contained and cwd-independent: builds a throwaway plugins/ tree with
# fixture plugins whose prose makes known-good and known-bad count claims, runs
# the checker against it, and asserts on exit code + output. Mutates only its own
# mktemp dir. The SUT resolves its paths relative to its own location, so the
# fixture tree carries a copy of it.
#
# The load-bearing assertions are the NEGATIVE ones. A gate that only proves it
# catches a wrong number is half a gate: this defect's failure mode in practice
# is a detector so eager that contributors reword around it, so the cases
# asserting that ordinary prose ("gate one skill", "nine skills moved into three
# new plugins") does NOT flag matter as much as the ones asserting a drift does.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-skill-count-claims.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts"
cp "$SUT_SRC" "$TMP/scripts/check-skill-count-claims.sh"
SUT="$TMP/scripts/check-skill-count-claims.sh"
EXEMPTIONS="$TMP/scripts/skill-count-claim-exemptions.txt"
: >"$EXEMPTIONS"

make_skill() {
  # plugin, skill
  mkdir -p "$TMP/plugins/$1/skills/$2"
  printf -- '---\nname: %s\ndescription: "fixture"\n---\n' "$2" >"$TMP/plugins/$1/skills/$2/SKILL.md"
}

readme() {
  # plugin, body...
  local plugin="$1"
  shift
  printf '%s\n' "$@" >"$TMP/plugins/$plugin/README.md"
}

run() { (cd "$TMP" && bash "$SUT" "$@" 2>&1); }
run_rc() {
  (cd "$TMP" && bash "$SUT" "$@" >/dev/null 2>&1)
  printf '%d' "$?"
}

# --- fixtures -------------------------------------------------------------

# alpha: 3 skills, every claim correct, in several grammars.
make_skill alpha one
make_skill alpha two
make_skill alpha three
readme alpha \
  'A plugin bundling three skills for one job.' \
  'Three skills, one concern: fixtures.' \
  'Only the first has prerequisites; the other two skills are zero-config.'

# beta: 4 skills but the prose still says two, in both grammars. Also carries a
# spelled claim inside the manifest description, which is where a plugin's count
# is most often read and least often re-read.
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

# gamma: 2 skills, and prose that a naive number-and-the-word-skills detector
# would flag but which asserts nothing about the plugin's size.
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

# delta: a CHANGELOG whose historical count is deliberately wrong for today's
# tree. Rewriting it would falsify the release it describes, so it is out of
# scope by design and must not flag.
make_skill delta a
make_skill delta b
make_skill delta c
readme delta 'Three skills, one concern: history.'
printf '%s\n' '- The plugin now bundles two skills.' \
  >"$TMP/plugins/delta/CHANGELOG.md"

# epsilon: a digit-form claim, wrong. Number words are the common form, but the
# remediation must speak whichever notation the author used.
make_skill epsilon a
make_skill epsilon b
readme epsilon 'A plugin bundling 5 skills for one job.'

# --- assertions -----------------------------------------------------------

out="$(run)"

# 1. Correct claims in several grammars are reported ok.
if [[ "$(grep -c '^ok .*alpha' <<<"$out")" -eq 3 ]]; then
  pass "all three correct alpha claims verify"
else
  fail "expected 3 ok rows for alpha: $out"
fi

# 2. The "other N skills" idiom is measured against total minus one.
if grep -q 'alpha .*two -> two (total minus one)' <<<"$out"; then
  pass "other-N idiom resolves to total minus one"
else
  fail "other-N idiom should compare against total-1: $out"
fi

# 3. A stale count flags, in prose and in the manifest alike.
if [[ "$(grep -c '^MISMATCH.*beta' <<<"$out")" -eq 3 ]]; then
  pass "stale count flags in README prose and plugin manifest"
else
  fail "expected 3 beta mismatches (2 README, 1 manifest): $out"
fi

# 4. Ordinary prose that merely mentions a number and skills does not flag.
if ! grep -q 'gamma' <<<"$(grep '^MISMATCH' <<<"$out")"; then
  pass "non-claim prose does not flag"
else
  fail "gamma prose should not produce any mismatch: $out"
fi

# 5. A definite-article reference is deliberately not a recognized form.
if ! grep -q 'the two skills this must not' <<<"$out"; then
  pass "definite-article reference is not treated as a claim"
else
  fail "'the two skills' should not be a recognized claim form: $out"
fi

# 6. CHANGELOG.md is out of scope: its historical count must not flag.
if ! grep -q 'CHANGELOG' <<<"$out"; then
  pass "CHANGELOG.md is not scanned"
else
  fail "CHANGELOG.md must be out of scope: $out"
fi

# 7. Digit-form claims are detected and answered in digits.
if grep -qE 'MISMATCH.*epsilon .*5 -> 2$' <<<"$out"; then
  pass "digit-form claim flags and its remediation stays numeric"
else
  fail "epsilon should flag as 5 -> 2 in digits: $out"
fi

# 8. --check fails while any mismatch stands.
rc="$(run_rc --check)"
if [[ "$rc" -eq 1 ]]; then
  pass "--check fails on a stale count"
else
  fail "--check should exit 1 with mismatches present (rc=$rc)"
fi

# 9. The failure message names the site and the correction in words.
out="$(run --check)"
if grep -q 'plugins/beta/README.md' <<<"$out" && grep -q 'Change it to "four"' <<<"$out"; then
  pass "failure names the site and the corrected spelled number"
else
  fail "failure should name site and corrected word: $out"
fi

# 10. An exemption suppresses a specific line, matched by substring.
printf 'plugins/beta/README.md|It ships two skills\n' >"$EXEMPTIONS"
out="$(run)"
if grep -q '^exempt .*beta/README.md' <<<"$out" &&
  [[ "$(grep -c '^MISMATCH.*beta' <<<"$out")" -eq 2 ]]; then
  pass "exemption suppresses exactly its own line"
else
  fail "exemption should suppress one beta line only: $out"
fi

# 11. A stale exemption is itself a failure, so the list can only shrink.
printf 'plugins/beta/README.md|a sentence that is not there\n' >"$EXEMPTIONS"
out="$(run --check)"
if grep -q 'no longer produces a mismatch' <<<"$out"; then
  pass "stale exemption fails --check"
else
  fail "stale exemption should fail: $out"
fi

# 12. An exemption pointing at a deleted file fails with that reason named.
printf 'plugins/zeta/README.md|anything\n' >"$EXEMPTIONS"
out="$(run --check)"
if grep -q 'no longer exists' <<<"$out"; then
  pass "exemption for a missing file fails with that reason"
else
  fail "missing-file exemption should fail: $out"
fi

# 13. A malformed exemption is a usage error, not a silent pass.
printf 'no-separator-here\n' >"$EXEMPTIONS"
rc="$(run_rc --check)"
if [[ "$rc" -eq 2 ]]; then
  pass "malformed exemption exits 2"
else
  fail "malformed exemption should exit 2 (rc=$rc)"
fi

# 14. A clean tree passes, and says how many claims it verified -- a gate that
#     found zero claims and one that verified twenty must not report alike.
: >"$EXEMPTIONS"
rm -rf "$TMP/plugins/beta" "$TMP/plugins/epsilon"
out="$(run --check)"
rc="$(run_rc --check)"
if [[ "$rc" -eq 0 ]] && grep -qE 'All [0-9]+ skill-count claim' <<<"$out"; then
  pass "clean tree passes and reports its claim count"
else
  fail "clean tree should pass with a count (rc=$rc): $out"
fi

# 15. A tree with no claims at all says so rather than reporting success.
CLEAN="$(mktemp -d)"
mkdir -p "$CLEAN/scripts" "$CLEAN/plugins/solo/skills/only"
cp "$SUT_SRC" "$CLEAN/scripts/check-skill-count-claims.sh"
printf -- '---\nname: only\n---\n' >"$CLEAN/plugins/solo/skills/only/SKILL.md"
printf 'No counts here.\n' >"$CLEAN/plugins/solo/README.md"
out="$( (cd "$CLEAN" && bash "$CLEAN/scripts/check-skill-count-claims.sh" 2>&1))"
if grep -q 'No skill-count claims found' <<<"$out"; then
  pass "a tree with no claims says so"
else
  fail "no-claims tree should say so: $out"
fi
rm -rf "$CLEAN"

# 16. Unknown mode is a usage error.
rc="$(run_rc --bogus)"
if [[ "$rc" -eq 2 ]]; then
  pass "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
