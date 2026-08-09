#!/usr/bin/env bash
# Black-box contract test for check-evals-quality.sh.
#
# Self-contained and cwd-independent: builds throwaway fixture eval sets —
# each seeding exactly one defect — runs the lint, and asserts on exit code
# and the specific Q-check finding. A clean rich-form set proves the happy
# path stays silent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-evals-quality.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  printf 'FAIL - jq is required to run this test suite (and the SUT)\n' >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# make_evals <skill-name> <evals-json-body>: writes the file at the
# conventional <skill>/evals/evals.json location and echoes its path.
make_evals() {
  local name="$1" body="$2"
  mkdir -p "$TMP/$name/evals"
  printf '%s\n' "$body" >"$TMP/$name/evals/evals.json"
  printf '%s\n' "$TMP/$name/evals/evals.json"
}

run() { bash "$SUT" "$@"; }

# A criterion set that satisfies every WARN heuristic: specific phrasing,
# and one "does NOT" case for the Q9 set-coverage signal.
CLEAN='{
  "skill_name": "clean",
  "evals": [
    {
      "id": 1,
      "name": "happy-path",
      "prompt": "Do the thing to src/app.js.",
      "expected_output": "The change is applied to src/app.js only, and the resulting diff is surfaced to the user.",
      "expectations": [
        "Only src/app.js is modified",
        "The resulting diff is shown before the turn ends"
      ]
    },
    {
      "id": 2,
      "name": "guardrail-declines-wildcard",
      "prompt": "Just apply it to every file.",
      "expected_output": "The skill does NOT touch files outside the named target; it declines the wildcard and asks for an explicit list.",
      "expectations": [
        "The skill does NOT modify files it was not pointed at",
        "It asks for an explicit file list instead of widening scope"
      ]
    }
  ]
}'

# 1. --help exits 0 and prints the whole header without spilling into code.
out="$(run --help 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'Fixture resolution (Q4)' <<<"$out" &&
  ! grep -q 'set -uo pipefail' <<<"$out"; then
  pass "--help prints the full header and stops before code"
else
  fail "--help should print the complete header and stop at the first code line (rc=$rc): $out"
fi

# 2. No arguments is a usage error (exit 2).
out="$(run 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'Usage' <<<"$out"; then
  pass "no arguments exits 2 with usage"
else
  fail "no arguments should exit 2 (rc=$rc): $out"
fi

# 3. A missing input file is an environment error (exit 2), not a skip.
out="$(run "$TMP/absent/evals/evals.json" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'not a file' <<<"$out"; then
  pass "a missing input file exits 2"
else
  fail "a missing input file should exit 2 (rc=$rc): $out"
fi

# 4. Unparsable JSON is an environment error (exit 2) pointing at schema
#    validation — fail closed, never a silent skip.
f="$(make_evals broken-json '{ not json')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'schema validation' <<<"$out"; then
  pass "unparsable JSON exits 2 and points at schema validation"
else
  fail "unparsable JSON should exit 2 (rc=$rc): $out"
fi

# 5. A clean rich-form set passes with zero findings.
f="$(make_evals clean "$CLEAN")"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'PASS (0 warning' <<<"$out" && ! grep -q '^FAIL:' <<<"$out"; then
  pass "a clean rich-form set passes with zero findings"
else
  fail "a clean set should pass with no findings (rc=$rc): $out"
fi

# 6. Q1: duplicate case ids FAIL (exit 1) — including an int/string collision,
#    which is still ambiguous to a grader.
f="$(make_evals dup-id '{
  "skill_name": "dup-id",
  "evals": [
    {"id": 1, "prompt": "a", "expected_output": "The output names the duplicate id and does NOT proceed."},
    {"id": "1", "prompt": "b", "expected_output": "A second case whose id collides with the first after tostring."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'duplicate case id 1.*(Q1)' <<<"$out"; then
  pass "Q1: duplicate ids (incl. int/string collision) FAIL"
else
  fail "Q1 should flag duplicate ids (rc=$rc): $out"
fi

# 7. Q2: duplicate case names FAIL.
f="$(make_evals dup-name '{
  "skill_name": "dup-name",
  "evals": [
    {"id": 1, "name": "same-name", "prompt": "a", "expected_output": "The skill does NOT rename anything; output pins case one."},
    {"id": 2, "name": "same-name", "prompt": "b", "expected_output": "A second case reusing the first case name verbatim."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'duplicate case name same-name.*(Q2)' <<<"$out"; then
  pass "Q2: duplicate names FAIL"
else
  fail "Q2 should flag duplicate names (rc=$rc): $out"
fi

# 8. Q3: an empty / whitespace-only expectations item FAILs.
f="$(make_evals empty-item '{
  "skill_name": "empty-item",
  "evals": [
    {"id": 1, "prompt": "a", "expectations": ["The skill does NOT delete files", "   "]}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'non-gradeable expectations/assertions item.*(Q3)' <<<"$out"; then
  pass "Q3: whitespace-only criterion item FAILs"
else
  fail "Q3 should flag empty items (rc=$rc): $out"
fi

# 8b. Q3: null and empty-container items FAIL; a non-empty object item
#     passes (item shape is skill-author-defined — upstream compat).
f="$(make_evals nongradeable-items '{
  "skill_name": "nongradeable-items",
  "evals": [
    {"id": 1, "prompt": "a", "expectations": ["The skill does NOT delete files", null, {}, []]},
    {"id": 2, "prompt": "b", "assertions": [{"kind": "regex", "pattern": "^fix: "}]}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && [[ "$(grep -c 'non-gradeable expectations/assertions item.*(Q3)' <<<"$out")" -eq 3 ]] &&
  ! grep -q 'id=2' <<<"$out"; then
  pass "Q3: null and empty containers FAIL; a structured item passes"
else
  fail "Q3 should flag null/empty containers and allow structured items (rc=$rc): $out"
fi

# 8c. Q3: a whitespace-only sole-criterion expected_output FAILs even when it
#     clears the Q8 length floor, and does not double-report as Q8.
f="$(make_evals ws-only-sole '{
  "skill_name": "ws-only-sole",
  "evals": [
    {"id": 1, "prompt": "a", "expected_output": "                                                  "}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'whitespace-only expected_output is the sole grading criterion.*(Q3)' <<<"$out" &&
  ! grep -q '(Q8)' <<<"$out"; then
  pass "Q3: whitespace-only sole expected_output FAILs without a Q8 double report"
else
  fail "Q3 should flag a whitespace-only sole expected_output once (rc=$rc): $out"
fi

# 9. Q4: a files entry that resolves nowhere FAILs; entries resolving
#    relative to the skill dir or the evals dir pass.
mkdir -p "$TMP/fixtures-ok/evals/fixtures"
printf 'fixture\n' >"$TMP/fixtures-ok/evals/fixtures/sample.md"
mkdir -p "$TMP/fixtures-ok/.claude"
printf 'config\n' >"$TMP/fixtures-ok/.claude/config.md"
f="$(make_evals fixtures-ok '{
  "skill_name": "fixtures-ok",
  "evals": [
    {"id": 1, "prompt": "a", "files": ["evals/fixtures/sample.md", ".claude/config.md", "fixtures/sample.md"],
     "expected_output": "The case does NOT need more fixtures; all three roots resolve."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q '(Q4)' <<<"$out"; then
  pass "Q4: skill-dir- and evals-dir-relative fixtures both resolve"
else
  fail "Q4 should resolve fixtures against both roots (rc=$rc): $out"
fi

f="$(make_evals fixtures-missing '{
  "skill_name": "fixtures-missing",
  "evals": [
    {"id": 1, "name": "needs-fixture", "prompt": "a", "files": ["evals/fixtures/nope.md"],
     "expected_output": "The case does NOT resolve its fixture; the lint must say so."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'files entry "evals/fixtures/nope.md" not found.*(Q4)' <<<"$out" &&
  grep -q 'case needs-fixture (id=1)' <<<"$out"; then
  pass "Q4: an unresolvable files entry FAILs, naming the case"
else
  fail "Q4 should flag a missing fixture (rc=$rc): $out"
fi

# 9b. Q4: traversal and absolute paths are rejected before the existence
#     test — an escaping entry must never pass by pointing at a real host
#     file (evals/../.. resolves to a directory that exists).
f="$(make_evals fixtures-escape '{
  "skill_name": "fixtures-escape",
  "evals": [
    {"id": 1, "prompt": "a", "files": ["evals/../../fixtures-escape", "/etc/hosts"],
     "expected_output": "The lint does NOT follow either entry outside the documented fixture roots."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && [[ "$(grep -c 'escapes the documented fixture roots.*(Q4)' <<<"$out")" -eq 2 ]]; then
  pass "Q4: absolute and ..-traversal entries FAIL without an existence probe"
else
  fail "Q4 should reject escaping entries before the -e test (rc=$rc): $out"
fi

# 10. Q5: a case carrying BOTH expectations and assertions WARNs (exit 0).
f="$(make_evals both-fields '{
  "skill_name": "both-fields",
  "evals": [
    {"id": 1, "prompt": "a",
     "expectations": ["The skill does NOT push"],
     "assertions": ["The commit exists on the current branch"]}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'BOTH expectations and assertions.*(Q5)' <<<"$out"; then
  pass "Q5: expectations+assertions on one case WARNs, exit 0"
else
  fail "Q5 should warn on mixed field names (rc=$rc): $out"
fi

# 11. Q6: two cases with identical prompt AND files WARN; same prompt with
#     different files does not.
f="$(make_evals dup-prompt '{
  "skill_name": "dup-prompt",
  "evals": [
    {"id": 1, "prompt": "same prompt", "expected_output": "The first case does NOT overlap in files."},
    {"id": 2, "prompt": "same prompt", "expected_output": "An identical prompt and files pair — residue."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'cases 1, 2 share an identical prompt and files.*(Q6)' <<<"$out"; then
  pass "Q6: identical prompt+files pair WARNs"
else
  fail "Q6 should warn on an identical prompt+files pair (rc=$rc): $out"
fi

mkdir -p "$TMP/dup-prompt-difffiles/evals/fixtures"
printf 'x\n' >"$TMP/dup-prompt-difffiles/evals/fixtures/a.md"
f="$(make_evals dup-prompt-difffiles '{
  "skill_name": "dup-prompt-difffiles",
  "evals": [
    {"id": 1, "prompt": "same prompt", "files": ["evals/fixtures/a.md"], "expected_output": "The fixture variant does NOT collide with the bare variant."},
    {"id": 2, "prompt": "same prompt", "expected_output": "The bare variant of the same prompt, distinguished by files."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q '(Q6)' <<<"$out"; then
  pass "Q6: same prompt with different files does not warn"
else
  fail "Q6 should not warn when files differ (rc=$rc): $out"
fi

# 12. Q7: a whole-item hedge WARNs; a verifiable criterion that merely
#     contains a hedge-adjacent word does not.
f="$(make_evals vague '{
  "skill_name": "vague",
  "evals": [
    {"id": 1, "prompt": "a", "expectations": ["The output is good", "The skill does NOT delete files"]}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'vague criterion "The output is good".*(Q7)' <<<"$out"; then
  pass "Q7: a whole-item hedge WARNs"
else
  fail "Q7 should warn on a vague whole-item criterion (rc=$rc): $out"
fi

f="$(make_evals not-vague '{
  "skill_name": "not-vague",
  "evals": [
    {"id": 1, "prompt": "a", "expectations": ["Touches no files", "The skill does NOT push", "Works through the checklist in order"]}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q '(Q7)' <<<"$out"; then
  pass "Q7: verifiable criteria containing hedge-adjacent words stay silent"
else
  fail "Q7 must not flag verifiable criteria (rc=$rc): $out"
fi

# 13. Q8: a thin sole-criterion expected_output WARNs; the same string with
#     expectations alongside does not.
f="$(make_evals thin '{
  "skill_name": "thin",
  "evals": [
    {"id": 1, "prompt": "The skill does NOT push anything.", "expected_output": "A short answer."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'sole grading criterion is a 15-char expected_output.*(Q8)' <<<"$out"; then
  pass "Q8: thin sole-criterion expected_output WARNs"
else
  fail "Q8 should warn on a thin sole criterion (rc=$rc): $out"
fi

f="$(make_evals thin-backed '{
  "skill_name": "thin-backed",
  "evals": [
    {"id": 1, "prompt": "a", "expected_output": "A short answer.",
     "expectations": ["The skill does NOT push", "The answer is one sentence naming the branch"]}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q '(Q8)' <<<"$out"; then
  pass "Q8: a thin expected_output backed by expectations stays silent"
else
  fail "Q8 must not flag a thin expected_output with expectations present (rc=$rc): $out"
fi

# 14. Q9: a set with no refusal/guardrail/anti-pattern language WARNs; the
#     clean set (which has a does-NOT case) already proved the silent side.
f="$(make_evals no-negative '{
  "skill_name": "no-negative",
  "evals": [
    {"id": 1, "prompt": "Summarize the file.", "expected_output": "A one-paragraph summary naming the three sections and their order, ending in a source line count."}
  ]
}')"
out="$(run "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'no case exhibits refusal/guardrail or anti-pattern language.*(Q9)' <<<"$out"; then
  pass "Q9: a set with no negative-behavior case WARNs"
else
  fail "Q9 should warn on a set with no negative-behavior case (rc=$rc): $out"
fi

# 15. Multi-file run: findings stay per-file, one failing file fails the run,
#     and the summary counts every input.
# Findings are asserted by path SUFFIX: on Git Bash the msys layer hands
# jq.exe a Windows-form path, so the absolute prefix differs from $TMP.
clean_f="$TMP/clean/evals/evals.json"
bad_f="$TMP/dup-id/evals/evals.json"
out="$(run "$clean_f" "$bad_f" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'dup-id/evals/evals.json: duplicate case id' <<<"$out" &&
  ! grep -q 'clean/evals/evals.json: ' <<<"$out" &&
  grep -q 'across 2 file(s)' <<<"$out"; then
  pass "multi-file: one failing file fails the run; findings name their file"
else
  fail "multi-file run should fail on the bad file only (rc=$rc): $out"
fi

printf '\n%d failure(s)\n' "$fails"
exit "$((fails > 0 ? 1 : 0))"
