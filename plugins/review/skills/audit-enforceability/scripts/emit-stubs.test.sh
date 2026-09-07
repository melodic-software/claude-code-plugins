#!/usr/bin/env bash
# Self-contained tests for emit-stubs.sh (no external test lib -- ships with the
# plugin; variants are built inline in a tmpdir from the shipped fixtures).
#
# The safety property under test: a stub is never admissible to the review fix
# pass. Three independent halves prove it -- the stub carries no findings-file
# marker (cases 2 and 11), the fix action's own admission predicate returns
# nothing over the stub home (case 3), and the writer refuses a stub home inside
# either the scan directory or the input's own directory (case 4).
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect any git call into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SCRIPT_DIR/emit-stubs.sh"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SKILL_DIR/evals/fixtures"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

# Both fixtures are copied into the tmpdir so a fence bug cannot write into the
# shipped fixture directory, and so the input-directory fence has a disposable
# subject.
INPUT_DIR="$TEST_TMPDIR/input"
mkdir -p "$INPUT_DIR"
cp "$FIXTURES/findings-one-per-rung.md" "$INPUT_DIR/findings-one-per-rung.md"
cp "$FIXTURES/classification-one-per-rung.tsv" "$INPUT_DIR/classification-one-per-rung.tsv"
FINDINGS="$INPUT_DIR/findings-one-per-rung.md"
CLASSES="$INPUT_DIR/classification-one-per-rung.tsv"

SCAN_DIR="$TEST_TMPDIR/memory/reviews/fixture"
mkdir -p "$SCAN_DIR"

count_files() {
  local dir="$1" n=0 f
  for f in "$dir"/*.md; do
    [[ -e "$f" ]] || continue
    n=$((n + 1))
  done
  printf '%d' "$n"
}

# --- Case 1: seven-row fixture -> seven stubs, one per rank, exit 0 ------------

OUT1="$TEST_TMPDIR/memory/enforceability/fixture"
out1_report="$(bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$OUT1" --scan-dir "$SCAN_DIR" 2>&1)"
assert_eq "case 1: exit 0 on the conforming fixture" "0" "$?"
assert_eq "case 1: seven stubs written, one per rank" "7" "$(count_files "$OUT1")"
assert_contains "case 1: the report names the count and the home" "$out1_report" "7 findings"
for rank in 01 02 03 04 05 06 07; do
  found=0
  for f in "$OUT1"/"$rank"-*.md; do
    [[ -e "$f" ]] && found=1
  done
  assert_eq "case 1: rank $rank has exactly one stub" "1" "$found"
done
assert_contains "case 1: the per-rung filename names the rung" "$(ls "$OUT1")" "04-semgrep-rule-"

# --- Case 2: stub type marker present, findings-file markers absent -----------

decl_ok=1
for f in "$OUT1"/*.md; do
  grep -q '^type: enforceability-stub$' "$f" || decl_ok=0
done
assert_eq "case 2: every stub declares type: enforceability-stub" "1" "$decl_ok"

forbidden_hits="$(grep -lE '^type: review-findings|^type: fix-pass-record|^branch:|^## Findings' "$OUT1"/*.md 2>/dev/null)"
assert_eq "case 2: no stub carries a forbidden findings-file marker" "" "$forbidden_hits"
assert_contains "case 2: the source branch is recorded under a key nothing scans for" \
  "$(cat "$OUT1"/01-*.md)" "source-branch: fixture"
assert_contains "case 2: the finding section heading is singular, not the table anchor" \
  "$(cat "$OUT1"/01-*.md)" "## Finding"

# --- Case 3: the fix action's Step 1 predicate returns nothing ----------------
#
# Replicated, not invoked: Step 1 admits every *.md directly in the resolved
# reviews directory whose frontmatter declares type: review-findings.
step1_hits="$(grep -l '^type: review-findings' "$OUT1"/*.md 2>/dev/null)"
assert_eq "case 3: the replicated fix-action admission predicate matches no stub" "" "$step1_hits"

# --- Case 4: both home fences ------------------------------------------------

FENCE_OUT="$TEST_TMPDIR/fence"
mkdir -p "$FENCE_OUT"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$SCAN_DIR" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 4: --out equal to --scan-dir exits 3" "3" "$?"
assert_eq "case 4: --out equal to --scan-dir wrote nothing" "0" "$(count_files "$SCAN_DIR")"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$SCAN_DIR/nested" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 4: --out under --scan-dir exits 3" "3" "$?"
assert_eq "case 4: --out under --scan-dir created no directory" "0" "$([[ -e "$SCAN_DIR/nested" ]] && echo 1 || echo 0)"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$INPUT_DIR" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 4: --out equal to the findings file's own directory exits 3" "3" "$?"
assert_eq "case 4: the findings directory gained no stub" "1" "$(count_files "$INPUT_DIR")"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$INPUT_DIR/stubs" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 4: --out under the findings file's own directory exits 3" "3" "$?"
assert_eq "case 4: --out under the findings directory created no directory" "0" "$([[ -e "$INPUT_DIR/stubs" ]] && echo 1 || echo 0)"

# A sibling whose name merely prefixes the scan directory is NOT under it.
SIBLING_OUT="${SCAN_DIR}-archive"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$SIBLING_OUT" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 4: a name-prefix sibling of --scan-dir is not fenced out" "0" "$?"

# --- Case 5: usage refusals ---------------------------------------------------

bash "$EMIT" --classes "$CLASSES" --out "$TEST_TMPDIR/c5a" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 5: missing --findings exits 2" "2" "$?"

bash "$EMIT" --findings "$TEST_TMPDIR/absent.md" --classes "$CLASSES" --out "$TEST_TMPDIR/c5b" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 5: a --findings path that does not exist exits 2" "2" "$?"

NONCONFORMING="$TEST_TMPDIR/nonconforming.md"
{
  printf -- '---\ntype: quality-gate-report\nbranch: fixture\n---\n\n'
  printf '## Findings\n\n'
  printf '| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |\n'
  printf '|---|---|---|---|---|---|---|\n'
  printf '| 1 | IMPORTANT | high | a.cs:1 | code-reviewer | text | act |\n'
} >"$NONCONFORMING"
bash "$EMIT" --findings "$NONCONFORMING" --classes "$CLASSES" --out "$TEST_TMPDIR/c5c" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 5: a file without type: review-findings exits 2" "2" "$?"
assert_eq "case 5: the non-conforming input produced no stub home" "0" "$([[ -e "$TEST_TMPDIR/c5c" ]] && echo 1 || echo 0)"

NOTABLE="$TEST_TMPDIR/no-table.md"
{
  printf -- '---\ntype: review-findings\nbranch: fixture\n---\n\n'
  printf '## Findings\n\nNothing parseable here.\n'
} >"$NOTABLE"
bash "$EMIT" --findings "$NOTABLE" --classes "$CLASSES" --out "$TEST_TMPDIR/c5d" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 5: a file whose Findings table does not parse exits 2" "2" "$?"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$TEST_TMPDIR/c5e" >/dev/null 2>&1
assert_eq "case 5: missing --scan-dir exits 2" "2" "$?"
assert_eq "case 5: missing --scan-dir wrote nothing" "0" "$([[ -e "$TEST_TMPDIR/c5e" ]] && echo 1 || echo 0)"

# --- Case 6: an escaped pipe reaches the stub unescaped and unsplit ------------

stub4="$(cat "$OUT1"/04-*.md)"
assert_contains "case 6: the escaped pipe is unescaped in the stub" "$stub4" 'string | null'
assert_not_contains "case 6: the escape sequence itself does not survive" "$stub4" 'string \| null'
assert_contains "case 6: the cell did not split on the escaped pipe" "$stub4" "- Action: Match the concatenation shape and parameterize the query."
assert_contains "case 6: the row's own Location survived the split" "$stub4" "- Location: src/Api/Search.ts:88"

# --- Case 7: a rank absent from --classes still gets a stub, via stdin ---------

OUT7="$TEST_TMPDIR/out7"
grep -v '^7	' "$CLASSES" >"$TEST_TMPDIR/classes-no-7.tsv"
out7_report="$(bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT7" --scan-dir "$SCAN_DIR" <"$TEST_TMPDIR/classes-no-7.tsv" 2>&1)"
assert_eq "case 7: the stdin classes form exits 0" "0" "$?"
assert_contains "case 7: the stdin form still reports every row" "$out7_report" "7 findings"
assert_eq "case 7: the unclassified rank still produced a stub" "7" "$(count_files "$OUT7")"
stub7="$(cat "$OUT7"/07-*.md)"
assert_contains "case 7: the unclassified rank falls to rung llm-only" "$stub7" "rung: llm-only"
assert_contains "case 7: the unclassified rank is classed unclassified" "$stub7" "finding-class: unclassified"
assert_contains "case 7: the unclassified rank records basis unresolved" "$stub7" "class-basis: unresolved"
assert_contains "case 7: the unclassified rank has no owner" "$stub7" "owner: none"
assert_contains "case 7: the llm-only rung reaches the filename" "$(ls "$OUT7")" "07-llm-only-"

# A rank in the TSV that the table does not carry is a diagnostic, not a stub.
OUT7B="$TEST_TMPDIR/out7b"
cp "$CLASSES" "$TEST_TMPDIR/classes-extra.tsv"
printf '99\tstyle\tjudgment\teditorconfig-severity\tnowhere\n' >>"$TEST_TMPDIR/classes-extra.tsv"
extra_err="$(bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT7B" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-extra.tsv" 2>&1 >/dev/null)"
assert_eq "case 7: a TSV rank absent from the table still exits 0" "0" "$?"
assert_eq "case 7: a TSV rank absent from the table adds no stub" "7" "$(count_files "$OUT7B")"
assert_contains "case 7: a TSV rank absent from the table is a diagnostic" "$extra_err" "rank 99"

# --- Case 8: a re-run never overwrites ----------------------------------------

before_first="$(cat "$OUT1"/01-editorconfig-severity-src-api-ordering.cs-14.md)"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$OUT1" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 8: the second run exits 0" "0" "$?"
assert_eq "case 8: the second run added seven siblings rather than overwriting" "14" "$(count_files "$OUT1")"
assert_eq "case 8: the first run's stub is byte-identical after the re-run" "$before_first" \
  "$(cat "$OUT1"/01-editorconfig-severity-src-api-ordering.cs-14.md)"
assert_eq "case 8: the collision took the -2 suffix" "1" \
  "$([[ -e "$OUT1/01-editorconfig-severity-src-api-ordering.cs-14-2.md" ]] && echo 1 || echo 0)"

# --- Case 9: the By dimension re-render produces no extra stubs ---------------
#
# The fixture re-renders all seven rows under two dimension headings, so a
# whole-file table reader would emit fourteen.
dim_rows="$(grep -c '^| [0-9] |' "$FINDINGS")"
assert_eq "case 9: the fixture really does carry every row twice" "14" "$dim_rows"
assert_eq "case 9: the writer emitted N stubs, never 2N" "7" "$(count_files "$OUT7")"

# --- Case 10: a DEGRADED blockquote above the heading parses to the same N ----

DEGRADED="$TEST_TMPDIR/input/degraded-one-per-rung.md"
awk '
  /^## Findings/ && !done {
    print "> DEGRADED: two of five surfaces returned nothing."
    print "> code-reviewer: timed out after the dispatch window."
    print "> ci-log-auditor: no run to audit on this branch."
    print ""
    done = 1
  }
  { print }
' "$FINDINGS" >"$DEGRADED"
OUT10="$TEST_TMPDIR/out10"
bash "$EMIT" --findings "$DEGRADED" --classes "$CLASSES" --out "$OUT10" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 10: the DEGRADED variant exits 0" "0" "$?"
assert_eq "case 10: the DEGRADED blockquote is not read as a row" "7" "$(count_files "$OUT10")"
assert_eq "case 10: the DEGRADED variant really carries the blockquote" "3" \
  "$(grep -c '^> DEGRADED\|^> code-reviewer\|^> ci-log-auditor' "$DEGRADED")"

# --- Case 11 (guard): a forbidden marker reaching a written stub -------------
#
# The stub shape carries no findings-file marker, so the post-write self-check
# is only reachable through a value the caller supplied. The Next step section
# renders the owner verbatim, which is that path. This case proves the check
# fires and takes back every stub the run wrote, rather than asserting a guard
# nothing exercises.
OUT11="$TEST_TMPDIR/out11"
printf '1\tstyle\tjudgment\teditorconfig-severity\t## Findings\n' >"$TEST_TMPDIR/classes-poison.tsv"
poison_err="$(bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT11" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-poison.tsv" 2>&1 >/dev/null)"
assert_eq "case 11: a forbidden marker reaching a stub exits 4" "4" "$?"
assert_eq "case 11: every stub the run wrote was removed" "0" "$(count_files "$OUT11")"
assert_contains "case 11: the refusal names the fix pass" "$poison_err" "fix pass"

# --- Dry run ------------------------------------------------------------------

OUTDRY="$TEST_TMPDIR/outdry"
dry_out="$(bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$OUTDRY" --scan-dir "$SCAN_DIR" --dry-run 2>&1)"
assert_eq "dry run: exits 0" "0" "$?"
assert_eq "dry run: wrote nothing" "0" "$([[ -e "$OUTDRY" ]] && echo 1 || echo 0)"
assert_contains "dry run: printed a planned filename" "$dry_out" "01-editorconfig-severity-"

# --- Final report --------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
