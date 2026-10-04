#!/usr/bin/env bash
# Self-contained tests for emit-stubs.sh (no external test lib -- ships with the
# plugin; variants are built inline in a tmpdir from the shipped fixtures).
#
# The safety property under test: a stub is never admissible to the review fix
# pass. Three independent halves prove it -- the stub carries no findings-file
# marker (cases 2 and 11), the fix action's own admission predicate returns
# nothing over the stub home (case 3), and the writer refuses a stub home inside
# either the scan directory or the input's own directory (case 4). Cases 14 and
# 21 add the composed-home bounds: a `..` segment, a home outside --memory-root,
# and a last path segment outside the branch-slug charset.
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
SKIPPED=0

# skip_case <reason> — skip one optional case without exiting. Named to match
# the house helper so scripts/check-discriminating-test-skips.sh can see the
# branch. It never vacates the only discriminating coverage: both home fences
# are asserted unconditionally in case 4; case 12 adds the second-spelling arm
# on filesystems that can express one.
skip_case() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP: %s\n' "$1" >&2
}

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

# path_exists <path>... / dir_exists <dir>: 1 when any argument exists (as a
# directory, for dir_exists), 0 when none does. Probes that PRINT rather than
# set an exit code, like count_files above: every call site compares the answer
# as assert_eq's actual value.
path_exists() {
  local p
  for p in "$@"; do
    if [[ -e "$p" ]]; then
      printf '1'
      return
    fi
  done
  printf '0'
}
dir_exists() {
  if [[ -d "$1" ]]; then printf '1'; else printf '0'; fi
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
assert_eq "case 4: --out under --scan-dir created no directory" "0" "$(path_exists "$SCAN_DIR/nested")"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$INPUT_DIR" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 4: --out equal to the findings file's own directory exits 3" "3" "$?"
assert_eq "case 4: the findings directory gained no stub" "1" "$(count_files "$INPUT_DIR")"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$INPUT_DIR/stubs" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 4: --out under the findings file's own directory exits 3" "3" "$?"
assert_eq "case 4: --out under the findings directory created no directory" "0" "$(path_exists "$INPUT_DIR/stubs")"

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
assert_eq "case 5: the non-conforming input produced no stub home" "0" "$(path_exists "$TEST_TMPDIR/c5c")"

NOTABLE="$TEST_TMPDIR/no-table.md"
{
  printf -- '---\ntype: review-findings\nbranch: fixture\n---\n\n'
  printf '## Findings\n\nNothing parseable here.\n'
} >"$NOTABLE"
bash "$EMIT" --findings "$NOTABLE" --classes "$CLASSES" --out "$TEST_TMPDIR/c5d" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 5: a file whose Findings table does not parse exits 2" "2" "$?"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$TEST_TMPDIR/c5e" >/dev/null 2>&1
assert_eq "case 5: missing --scan-dir exits 2" "2" "$?"
assert_eq "case 5: missing --scan-dir wrote nothing" "0" "$(path_exists "$TEST_TMPDIR/c5e")"

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

# A TSV row whose first field is not a rank the table carries is refused whole:
# it is either a stray rank or a fragment of a broken row, and nothing is written.
OUT7B="$TEST_TMPDIR/out7b"
cp "$CLASSES" "$TEST_TMPDIR/classes-extra.tsv"
printf '99\tstyle\tjudgment\teditorconfig-severity\tnowhere\n' >>"$TEST_TMPDIR/classes-extra.tsv"
extra_err="$(bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT7B" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-extra.tsv" 2>&1 >/dev/null)"
assert_eq "case 7: a TSV rank absent from the table exits 2" "2" "$?"
assert_eq "case 7: a TSV rank absent from the table writes nothing" "0" "$(path_exists "$OUT7B")"
assert_contains "case 7: the refusal names the TSV line" "$extra_err" "line 8"
assert_contains "case 7: the refusal names the rank last" "$extra_err" ": 99"

printf 'abc\tstyle\tjudgment\teditorconfig-severity\tnowhere\n' >"$TEST_TMPDIR/classes-word.tsv"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$TEST_TMPDIR/out7c" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-word.tsv" >/dev/null 2>&1
assert_eq "case 7: a first field that is not a rank exits 2" "2" "$?"
assert_eq "case 7: a first field that is not a rank writes nothing" "0" "$(path_exists "$TEST_TMPDIR/out7c")"

# --- Case 8: a re-run never overwrites ----------------------------------------

before_first="$(cat "$OUT1"/01-editorconfig-severity-src-api-ordering.cs-14.md)"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$OUT1" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 8: the second run exits 0" "0" "$?"
assert_eq "case 8: the second run added seven siblings rather than overwriting" "14" "$(count_files "$OUT1")"
assert_eq "case 8: the first run's stub is byte-identical after the re-run" "$before_first" \
  "$(cat "$OUT1"/01-editorconfig-severity-src-api-ordering.cs-14.md)"
assert_eq "case 8: the collision took the -2 suffix" "1" \
  "$(path_exists "$OUT1/01-editorconfig-severity-src-api-ordering.cs-14-2.md")"

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

# --- Case 12 (guard): a second spelling of the same fenced directory ---------
#
# Comparing two spellings of ONE directory as strings reports "not within" and
# writes the stubs into the directory the fence protects. A symlink is the
# portable way to produce a second spelling; a host whose filesystem cannot
# express one skips this arm, and case 4 still asserts both fences.
CANON="$TEST_TMPDIR/canon"
mkdir -p "$CANON/reviews"
canon_arms=0

# Arm A: the shell layer's own second spelling. `pwd -W` yields the host's
# other absolute form of the same directory where one exists, and needs no
# filesystem feature at all. This is the arm that covers the host class the
# spelling defect was reported on.
CANON_ALT="$(cd "$CANON/reviews" && pwd -W 2>/dev/null || true)"
if [[ -n "$CANON_ALT" && "$CANON_ALT" != "$CANON/reviews" ]]; then
  canon_arms=$((canon_arms + 1))
  bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$CANON_ALT/stubs" \
    --scan-dir "$CANON/reviews" >/dev/null 2>&1
  assert_eq "case 12a: the shell layer's other spelling of --scan-dir is still fenced" "3" "$?"
  assert_eq "case 12a: the other spelling wrote nothing into the scan directory" "0" \
    "$(count_files "$CANON/reviews")"
  bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$CANON/reviews/stubs" \
    --scan-dir "$CANON_ALT" >/dev/null 2>&1
  assert_eq "case 12a: the fence holds with the spellings the other way round" "3" "$?"
fi

# Arm B: a symlinked spelling, where the filesystem can express one.
if ln -s "$CANON/reviews" "$CANON/link" 2>/dev/null && [[ -L "$CANON/link" ]]; then
  canon_arms=$((canon_arms + 1))
  bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$CANON/link/stubs" \
    --scan-dir "$CANON/reviews" >/dev/null 2>&1
  assert_eq "case 12b: a symlinked spelling of --scan-dir is still fenced" "3" "$?"
  assert_eq "case 12b: the symlinked spelling wrote nothing into the scan directory" "0" \
    "$(count_files "$CANON/reviews")"
  assert_eq "case 12b: the symlinked spelling created no stub directory" "0" \
    "$(path_exists "$CANON/reviews/stubs")"
fi

if [[ $canon_arms -eq 0 ]]; then
  skip_case "case 12: this host expresses no second absolute spelling of one directory (no pwd -W form, no symlinks)"
fi

# --- Case 13 (guard): a row an unescaped pipe shifted is reported ------------
#
# Such a row cannot be stubbed, and a success line whose count silently
# excludes it is the quiet-drop failure this reports instead.
SHIFTED="$TEST_TMPDIR/input/shifted.md"
awk '
  /^\| 7 \|/ && !done { sub(/hard to follow/, "hard | to follow"); done = 1 }
  { print }
' "$FINDINGS" >"$SHIFTED"
OUT13="$TEST_TMPDIR/out13"
shifted_err="$(bash "$EMIT" --findings "$SHIFTED" --classes "$CLASSES" --out "$OUT13" \
  --scan-dir "$SCAN_DIR" 2>&1 >/dev/null)"
assert_eq "case 13: a shifted row does not fail the run" "0" "$?"
assert_contains "case 13: the shifted row is reported per row" "$shifted_err" "unescaped pipe"
# The per-row diagnostic alone is not the fix: the SUCCESS line still counts
# only the rows that became stubs, so the run must also say the count excludes
# one. This assertion is what discriminates the fix from its absence.
assert_contains "case 13: the success line's count is declared incomplete" "$shifted_err" "WARNING:"
assert_contains "case 13: the warning names how many rows the count excludes" "$shifted_err" "1 further row(s)"
assert_eq "case 13: the shifted row produced no stub" "6" "$(count_files "$OUT13")"

# --- Case 14: a home that escapes the tree it was composed from --------------
#
# The branch slug the caller composes into the home comes from the findings
# file's own frontmatter, which nothing authenticates. A slug that reached the
# path unsanitized steers it out of the tree, and neither sibling fence sees
# that: the escaped path collides with nothing.
MEM_ROOT="$TEST_TMPDIR/memory"
ESCAPED="$MEM_ROOT/enforceability/../../../escape"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$ESCAPED" \
  --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 14: a home carrying a .. segment is refused" "3" "$?"
assert_eq "case 14: the escape target was never created" "0" \
  "$(path_exists "$TEST_TMPDIR/../../../escape" "$TEST_TMPDIR/escape")"

escape_err="$(bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$ESCAPED" \
  --scan-dir "$SCAN_DIR" 2>&1 >/dev/null)"
assert_contains "case 14: the refusal is visible, not silent" "$escape_err" "refusing:"
assert_contains "case 14: the refusal names the slug as the way a .. segment appears" "$escape_err" "branch slug"

# A home that escapes WITHOUT a `..` segment is caught by the anchor instead.
OUTSIDE="$TEST_TMPDIR/outside/enforceability/fixture"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$OUTSIDE" \
  --scan-dir "$SCAN_DIR" --memory-root "$MEM_ROOT" >/dev/null 2>&1
assert_eq "case 14: a home outside --memory-root is refused" "3" "$?"
assert_eq "case 14: the outside home was never created" "0" \
  "$(path_exists "$OUTSIDE")"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$MEM_ROOT" \
  --scan-dir "$SCAN_DIR" --memory-root "$MEM_ROOT" >/dev/null 2>&1
assert_eq "case 14: a home that IS the memory root is refused" "3" "$?"

# The anchor must not over-fence the home the caller actually composes.
ANCHORED="$MEM_ROOT/enforceability/anchored"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$ANCHORED" \
  --scan-dir "$SCAN_DIR" --memory-root "$MEM_ROOT" >/dev/null 2>&1
assert_eq "case 14: the composed home under --memory-root still writes" "0" "$?"
assert_eq "case 14: the composed home got its seven stubs" "7" "$(count_files "$ANCHORED")"

# The anchor accepts a second spelling of the same root.
ROOT_ALT="$MEM_ROOT/./enforceability/.."
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$ANCHORED" \
  --scan-dir "$SCAN_DIR" --memory-root "$ROOT_ALT" >/dev/null 2>&1
assert_eq "case 14: a .. segment in --memory-root is refused too" "3" "$?"

# --- Case 15: a ".." in the INPUT path moves the directory being fenced ------
#
# The findings directory is one of the two fenced homes, and it is derived from
# --findings. A `..` there resolves one way for the OS and another way for a
# lexical normalizer, so the directory fenced against stops being the one the
# file sits in. Refused rather than resolved, for the same reason as --out.
DOTDOT_IN="$INPUT_DIR/../input/findings-one-per-rung.md"
bash "$EMIT" --findings "$DOTDOT_IN" --classes "$CLASSES" --out "$INPUT_DIR/stubs15" \
  --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 15: a findings path carrying a .. segment is refused" "3" "$?"
assert_eq "case 15: the refused input path created no stub home" "0" \
  "$(path_exists "$INPUT_DIR/stubs15")"

# --- Case 16: a write that fails is detected and taken back ------------------
#
# A stub that never reached disk would be read as clean by the marker
# self-check, so the run must notice the failed write itself. The failure is
# forced with a target the OS refuses to open for writing.
OUT16="$TEST_TMPDIR/out16"
mkdir -p "$OUT16"
chmod 555 "$OUT16" 2>/dev/null || true
# Probe first: a host that ignores a read-only directory bit cannot force the
# failure at all, and asserting against it would score a vacuous pass.
if (: >"$OUT16/.probe") 2>/dev/null; then
  rm -f "$OUT16/.probe"
  chmod 755 "$OUT16" 2>/dev/null || true
  skip_case "case 16: this host writes into a read-only directory, so a failed stub write cannot be forced here"
else
  write_err="$(bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$OUT16" \
    --scan-dir "$SCAN_DIR" 2>&1 >/dev/null)"
  write_exit=$?
  chmod 755 "$OUT16" 2>/dev/null || true
  if [[ "$write_exit" -eq 0 ]]; then
    fail "case 16: a failed stub write is detected" "a non-zero exit" "exit 0 with a clean report"
  else
    pass "case 16: a failed stub write is detected"
    assert_contains "case 16: the refusal names the failed write" "$write_err" "failed"
    assert_eq "case 16: no stub survives a run whose write failed" "0" "$(count_files "$OUT16")"
  fi
fi

# --- Case 17: a case-different spelling of a fenced directory ----------------
#
# On a case-insensitive volume two case-different spellings name ONE directory,
# and `pwd -P` does not fold segment case, so canonicalization cannot close it.
# The comparison is case-insensitive in the fail-closed direction, so this is
# refused on every host.
CASEDIR="$TEST_TMPDIR/casefence"
mkdir -p "$CASEDIR/reviews/feat-x"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
  --out "$CASEDIR/REVIEWS/FEAT-X/stubs" --scan-dir "$CASEDIR/reviews/feat-x" >/dev/null 2>&1
assert_eq "case 17: a case-different spelling of --scan-dir is refused" "3" "$?"
assert_eq "case 17: nothing landed in the scan directory" "0" "$(count_files "$CASEDIR/reviews/feat-x")"
assert_eq "case 17: the case-different home was not created" "0" \
  "$(path_exists "$CASEDIR/REVIEWS/FEAT-X/stubs")"

bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
  --out "$(printf '%s' "$INPUT_DIR" | tr '[:lower:]' '[:upper:]')/stubs17" \
  --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 17: a case-different spelling of the findings directory is refused" "3" "$?"

# --- Case 18: a network-share spelling is refused ----------------------------
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
  --out "//localhost/share/stubs" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 18: a UNC --out is refused" "3" "$?"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
  --out "$TEST_TMPDIR/out18" --scan-dir "//localhost/share/reviews" >/dev/null 2>&1
assert_eq "case 18: a UNC --scan-dir is refused" "3" "$?"
assert_eq "case 18: the UNC run created no stub home" "0" \
  "$(path_exists "$TEST_TMPDIR/out18")"

# --- Case 19: an empty --memory-root does not silently disable the anchor ----
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$TEST_TMPDIR/out19" \
  --scan-dir "$SCAN_DIR" --memory-root "" >/dev/null 2>&1
assert_eq "case 19: an explicitly empty --memory-root is a usage refusal" "2" "$?"
assert_eq "case 19: the empty-root run wrote nothing" "0" \
  "$(path_exists "$TEST_TMPDIR/out19")"

# --- Case 20: the rollback survives an option-shaped stub home ---------------
#
# The exit-4 rollback promises that no stub carrying a findings-file marker
# stays on disk. A home whose name starts with `-` turns every path `rm` is
# handed into an option, so the promise is only kept if the removal is fenced
# off from option parsing.
OUT20="$TEST_TMPDIR/dash"
mkdir -p "$OUT20"
(
  cd "$OUT20" || exit 1
  printf '1\tstyle\tjudgment\teditorconfig-severity\tbranch: evil\n' |
    bash "$EMIT" --findings "$FINDINGS" --classes - --out "-" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
)
dash_exit=$?
assert_eq "case 20: the option-shaped home still exits 4 on a forbidden marker" "4" "$dash_exit"
dash_left="$(count_files "$OUT20/-")"
assert_eq "case 20: the rollback removed every stub despite the option-shaped path" "0" "$dash_left"

# --- Case 21: the last path segment must match the branch-slug charset -----
#
# --memory-root bounds where a composed home may sit. The last path segment is
# the branch slug itself, taken from operator-supplied frontmatter, and a
# charset miss is an unsanitized value that does not need `..` to be wrong.
# Checked even when the home already sits under --memory-root, and even when
# the caller omitted the anchor: neither bound is a substitute for the other.
CHARSET_ROOT="$TEST_TMPDIR/charset-root"
CHARSET_BAD="$CHARSET_ROOT/enforceability/Feat-X"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$CHARSET_BAD" \
  --scan-dir "$SCAN_DIR" --memory-root "$CHARSET_ROOT" >/dev/null 2>&1
assert_eq "case 21: an uppercase last segment under --memory-root is refused" "3" "$?"
assert_eq "case 21: the uppercase home was never created" "0" \
  "$(path_exists "$CHARSET_BAD")"

charset_err="$(bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$CHARSET_BAD" \
  --scan-dir "$SCAN_DIR" --memory-root "$CHARSET_ROOT" 2>&1 >/dev/null)"
assert_contains "case 21: the refusal names the charset" "$charset_err" "charset"
assert_contains "case 21: the refusal names the branch slug" "$charset_err" "branch slug"

CHARSET_SPACE="$TEST_TMPDIR/charset-space/feat x"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$CHARSET_SPACE" \
  --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 21: a last segment with a space is refused without --memory-root" "3" "$?"
assert_eq "case 21: the spaced home was never created" "0" \
  "$(path_exists "$CHARSET_SPACE")"

CHARSET_OK="$CHARSET_ROOT/enforceability/feat-x"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$CHARSET_OK" \
  --scan-dir "$SCAN_DIR" --memory-root "$CHARSET_ROOT" >/dev/null 2>&1
assert_eq "case 21: a last segment inside the charset still writes" "0" "$?"
assert_eq "case 21: the charset-ok home got its seven stubs" "7" "$(count_files "$CHARSET_OK")"
# --- Case 22: a NON-ASCII case-variant spelling ------------------------------
#
# A string compare folds ASCII only when no locale is set, while the filesystem
# folds all of Unicode, so a non-ASCII segment spelled two ways is one directory
# the string compare calls two. This is the arm case 17 cannot cover.
#
# This case PRE-CREATES the scan directory, so the filesystem has an inode to
# compare and existence decides who answers. A volume that folds the two
# spellings to one directory refuses (exit 3). A volume that keeps them
# distinct writes (exit 0), and nothing lands in --scan-dir. The suite must
# not treat those two outcomes as equivalent: a flip from write to refuse on
# a case-sensitive volume is a regression of the existing-inode arm. Case 27
# is the sibling for the arm where neither spelling exists yet, which the
# fold still decides.
UNI="$TEST_TMPDIR/uni"
if mkdir -p "$UNI/réviews/feat-x" 2>/dev/null && [[ -d "$UNI/réviews/feat-x" ]]; then
  cp "$FINDINGS" "$UNI/réviews/feat-x/review-findings.md"
  bash "$EMIT" --findings "$UNI/réviews/feat-x/review-findings.md" --classes "$CLASSES" \
    --out "$UNI/RÉVIEWS/feat-x/stubs" --scan-dir "$UNI/réviews/feat-x" >/dev/null 2>&1
  uni_exit=$?
  uni_landed="$(count_files "$UNI/réviews/feat-x/stubs")"
  if [[ "$uni_landed" -gt 0 ]]; then
    fail "case 22: a non-ASCII case variant is fenced" "no stub inside --scan-dir" "$uni_landed stubs landed there"
  else
    mkdir -p "$UNI/caseprobe/reviews"
    if [[ -d "$UNI/caseprobe/REVIEWS" ]]; then
      assert_eq "case 22: a folding volume refuses a non-ASCII case variant of --scan-dir" "3" "$uni_exit"
    else
      assert_eq "case 22: a case-sensitive volume writes into the distinct spelling" "0" "$uni_exit"
      assert_eq "case 22: the distinct home received stubs" "7" "$(count_files "$UNI/RÉVIEWS/feat-x/stubs")"
    fi
  fi
else
  skip_case "case 22: this filesystem does not accept a non-ASCII path segment"
fi

# --- Case 23: whitespace and bare CR before a forbidden marker ---------------
#
# A reader downstream may split on a bare CR and may tolerate leading space, so
# a check modeling only LF-terminated column-0 markers would pass a stub such a
# reader still sees as declaring one.
OUT22="$TEST_TMPDIR/out22"
printf '1\tstyle\tjudgment\teditorconfig-severity\t branch: evil\n' >"$TEST_TMPDIR/classes-ws.tsv"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT22" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-ws.tsv" >/dev/null 2>&1
assert_eq "case 23: a marker behind leading whitespace still exits 4" "4" "$?"
assert_eq "case 23: the whitespace-marker run left no stub" "0" "$(count_files "$OUT22")"

OUT22B="$TEST_TMPDIR/out22b"
printf '1\tstyle\tjudgment\teditorconfig-severity\tpre\rbranch: evil\n' >"$TEST_TMPDIR/classes-cr.tsv"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT22B" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-cr.tsv" >/dev/null 2>&1
assert_eq "case 23: a marker after an embedded bare CR still exits 4" "4" "$?"
assert_eq "case 23: the CR-marker run left no stub" "0" "$(count_files "$OUT22B")"

# --- Case 24: a segment ending in a dot or a space is refused ----------------
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$SCAN_DIR." \
  --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 24: a home whose segment ends in a dot is refused" "3" "$?"
bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$TEST_TMPDIR/out23 " \
  --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 24: a home whose segment ends in a space is refused" "3" "$?"

# --- Case 25: the rollback leaves pre-existing state alone -------------------
OUT24="$TEST_TMPDIR/out24"
mkdir -p "$OUT24"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT24" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-poison.tsv" >/dev/null 2>&1
assert_eq "case 25: the marker refusal still exits 4" "4" "$?"
assert_eq "case 25: a home the run did NOT create survives its rollback" "1" \
  "$(dir_exists "$OUT24")"
assert_eq "case 25: but it holds no stub" "0" "$(count_files "$OUT24")"

# --- Case 26: a row with an empty Rank is stubbed, not lost ------------------
EMPTY_RANK="$TEST_TMPDIR/input/empty-rank.md"
awk '/^\| 7 \|/ { sub(/^\| 7 \|/, "|  |") } { print }' "$FINDINGS" >"$EMPTY_RANK"
OUT25="$TEST_TMPDIR/out25"
# Rank 7 is gone from the table, so the TSV that classifies it would be refused;
# the TSV without it isolates the empty-Rank behavior.
bash "$EMIT" --findings "$EMPTY_RANK" --classes "$TEST_TMPDIR/classes-no-7.tsv" --out "$OUT25" \
  --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 26: an empty Rank cell does not fail the run" "0" "$?"
assert_eq "case 26: the empty-Rank row still produced a stub" "7" "$(count_files "$OUT25")"

# --- Case 27: a non-ASCII case variant of an ABSENT --scan-dir ---------------
#
# The arm case 22 cannot reach. With the scan directory pre-created there is an
# inode to compare and the walk settles it; with NEITHER spelling present there
# is nothing to ask the filesystem, and an ASCII-only fold reads `RÉVIEWS` and
# `réviews` as two directories that a folding volume resolves to one. The
# refusal must be the same exit 3 the pre-created arm gives, and it is asserted
# on both kinds of volume: refusing a genuinely distinct sibling that differs
# only in case is the documented cost of the fence, exactly as case 17 asserts
# it for the ASCII spelling.
UNI_OK=0
if mkdir -p "$TEST_TMPDIR/uni-probe/réviews" 2>/dev/null && [[ -d "$TEST_TMPDIR/uni-probe/réviews" ]]; then
  UNI_OK=1
  rm -rf "$TEST_TMPDIR/uni-probe"
fi

if [[ "$UNI_OK" -eq 1 ]]; then
  ABSENT="$TEST_TMPDIR/absent-uni"
  mkdir -p "$ABSENT"
  bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
    --out "$ABSENT/réviews/feat-x" --scan-dir "$ABSENT/RÉVIEWS/feat-x" \
    --memory-root "$ABSENT" >/dev/null 2>&1
  assert_eq "case 27: an absent non-ASCII case variant of --scan-dir is refused" "3" "$?"
  assert_eq "case 27: the stub home was never created" "0" \
    "$(path_exists "$ABSENT/réviews/feat-x")"
  assert_eq "case 27: the scan directory was never created either" "0" \
    "$(path_exists "$ABSENT/RÉVIEWS/feat-x")"
  absent_left=0
  for f in "$ABSENT"/*; do
    [[ -e "$f" ]] && absent_left=$((absent_left + 1))
  done
  assert_eq "case 27: the refused run created nothing at all under the root" "0" "$absent_left"
else
  skip_case "case 27: this filesystem does not accept a non-ASCII path segment"
fi

# --- Case 28: a non-ASCII case variant of the findings directory -------------
#
# The second anchor. Its ancestor cannot be absent: --findings must name a file
# that exists, which pins its directory into existence, so existence decides
# who answers the same way case 22 does. A folding volume settles the pair by
# inode and refuses. A volume that keeps the spellings distinct writes into
# the other directory; the fold does not get to refuse an inode the filesystem
# already named.
if [[ "$UNI_OK" -eq 1 ]]; then
  UNIF="$TEST_TMPDIR/uni-findings"
  mkdir -p "$UNIF/réviews/feat-x"
  cp "$FINDINGS" "$UNIF/réviews/feat-x/review-findings.md"
  bash "$EMIT" --findings "$UNIF/réviews/feat-x/review-findings.md" --classes "$CLASSES" \
    --out "$UNIF/RÉVIEWS/feat-x/stubs" --scan-dir "$TEST_TMPDIR/elsewhere28" >/dev/null 2>&1
  unif_exit=$?
  mkdir -p "$UNIF/caseprobe/reviews"
  if [[ -d "$UNIF/caseprobe/REVIEWS" ]]; then
    assert_eq "case 28: a folding volume refuses a non-ASCII case variant of the findings directory" "3" "$unif_exit"
    assert_eq "case 28: the case-variant stub home was never created" "0" \
      "$(path_exists "$UNIF/RÉVIEWS/feat-x/stubs")"
  else
    assert_eq "case 28: a case-sensitive volume writes into the distinct findings-dir spelling" "0" "$unif_exit"
    assert_eq "case 28: the distinct home received stubs" "7" "$(count_files "$UNIF/RÉVIEWS/feat-x/stubs")"
  fi
  assert_eq "case 28: the findings directory still holds only its own file" "1" \
    "$(count_files "$UNIF/réviews/feat-x")"
else
  skip_case "case 28: this filesystem does not accept a non-ASCII path segment"
fi

# --- Case 30: existing siblings the coarse fold would collide ----------------
#
# `révu` and `rêvu` both exist and the filesystem names them as two inodes.
# The placeholder fold would still spell them alike, but the inode walk runs
# first, so the write into the sibling proceeds. The over-refusal is paid only
# for unresolved tails (case 27), not for directories the filesystem can
# already tell apart.
if [[ "$UNI_OK" -eq 1 ]]; then
  SIB="$TEST_TMPDIR/sibling-uni"
  if mkdir -p "$SIB/révu/feat-x" "$SIB/rêvu" 2>/dev/null &&
    [[ -d "$SIB/révu/feat-x" && -d "$SIB/rêvu" ]] &&
    ! [[ "$SIB/révu" -ef "$SIB/rêvu" ]]; then
    cp "$FINDINGS" "$SIB/révu/feat-x/review-findings.md"
    bash "$EMIT" --findings "$SIB/révu/feat-x/review-findings.md" --classes "$CLASSES" \
      --out "$SIB/rêvu/feat-x/stubs" --scan-dir "$SIB/révu/feat-x" >/dev/null 2>&1
    assert_eq "case 30: existing non-ASCII siblings the fold would collide still write" "0" "$?"
    assert_eq "case 30: the sibling home received stubs" "7" "$(count_files "$SIB/rêvu/feat-x/stubs")"
    sib_landed="$(count_files "$SIB/révu/feat-x/stubs")"
    assert_eq "case 30: nothing landed in the scan directory" "0" "$sib_landed"
  else
    skip_case "case 30: this filesystem does not keep révu and rêvu as distinct directories"
  fi
else
  skip_case "case 30: this filesystem does not accept a non-ASCII path segment"
fi

# --- Case 29: the rollback removes every level the run created ---------------
#
# `mkdir -p` creates every absent level of the home, so a rollback that removed
# only the innermost one left an empty parent behind and the refused run did not
# leave the tree as it found it. Both halves are asserted: every created level
# goes, and no level that was already there does.
RB="$TEST_TMPDIR/rollback"
mkdir -p "$RB"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$RB/a/b" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-poison.tsv" >/dev/null 2>&1
assert_eq "case 29: a two-level home still exits 4 on a forbidden marker" "4" "$?"
assert_eq "case 29: the innermost created level is gone" "0" \
  "$(path_exists "$RB/a/b")"
assert_eq "case 29: the parent level the same mkdir created is gone too" "0" \
  "$(path_exists "$RB/a")"
assert_eq "case 29: the level the run did not create survives" "1" \
  "$(dir_exists "$RB")"

RB2="$TEST_TMPDIR/rollback2/kept"
mkdir -p "$RB2"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$RB2/made" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-poison.tsv" >/dev/null 2>&1
assert_eq "case 29: a home whose parent already existed still exits 4" "4" "$?"
assert_eq "case 29: the one level this run created is gone" "0" \
  "$(path_exists "$RB2/made")"
assert_eq "case 29: the prepared parent survives the rollback" "1" \
  "$(dir_exists "$RB2")"

# Spellings of the SAME home that a raw-string walk reads as a different chain.
# A trailing slash makes the first step up yield the same directory twice, and a
# `.` segment makes it yield a path that already exists, so a walk over the raw
# --out stops before it has recorded the parent it is about to create.
RB3="$TEST_TMPDIR/rollback3"
mkdir -p "$RB3"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$RB3/a/b/" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-poison.tsv" >/dev/null 2>&1
assert_eq "case 29: a trailing-slash home still exits 4" "4" "$?"
assert_eq "case 29: a trailing slash does not strand the parent level" "0" \
  "$(path_exists "$RB3/a")"

RB4="$TEST_TMPDIR/rollback4"
mkdir -p "$RB4"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$RB4/a/./b" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-poison.tsv" >/dev/null 2>&1
assert_eq "case 29: a home with a dot segment still exits 4" "4" "$?"
assert_eq "case 29: a dot segment does not strand the parent level" "0" \
  "$(path_exists "$RB4/a")"

# --- Case 31: NFC versus NFD of one directory --------------------------------
#
# The pair the case fold does not cover. U+00E9 (NFC) and e + U+0301 (NFD)
# are one directory on a normalization-insensitive volume and two directories
# on NTFS and ext4. The absent-tail arm must refuse on the former, at the same
# exit 3 an existing directory gets, and must still write on the latter.
# A runner whose filesystem accepts neither spelling skips, and the reason
# names that property, the same way case 16 does. The string fold itself is
# asserted by --check-normalization-fold, including under LC_ALL=C, because
# this host may be byte-exact and then never executes the refusal arm.
bash "$EMIT" --check-normalization-fold >/dev/null 2>&1
assert_eq "case 31: NFC and NFD fold together only when the volume is normalizing" "0" "$?"
env LC_ALL=C bash "$EMIT" --check-normalization-fold >/dev/null 2>&1
assert_eq "case 31: the same fold holds under LC_ALL=C" "0" "$?"

NORM31="$TEST_TMPDIR/norm31"
mkdir -p "$NORM31"
NFC_ACUTE=$'\xc3\xa9'
NFD_ACUTE=$'e\xcc\x81'
NFC_NAME="r${NFC_ACUTE}views"
NFD_NAME="r${NFD_ACUTE}views"
norm31_kind=""
if mkdir -- "$NORM31/probe-$NFC_NAME" 2>/dev/null && [[ -d "$NORM31/probe-$NFC_NAME" ]]; then
  if mkdir -- "$NORM31/probe-$NFD_NAME" 2>/dev/null; then
    if [[ "$NORM31/probe-$NFC_NAME" -ef "$NORM31/probe-$NFD_NAME" ]]; then
      norm31_kind="normalizing"
    else
      norm31_kind="byte-exact"
    fi
  elif [[ -d "$NORM31/probe-$NFD_NAME" && "$NORM31/probe-$NFC_NAME" -ef "$NORM31/probe-$NFD_NAME" ]]; then
    norm31_kind="normalizing"
  else
    norm31_kind="unreadable"
  fi
  rmdir -- "$NORM31/probe-$NFD_NAME" 2>/dev/null || true
  rmdir -- "$NORM31/probe-$NFC_NAME" 2>/dev/null || true
else
  norm31_kind="no-nonascii"
fi

if [[ "$norm31_kind" == "no-nonascii" ]]; then
  skip_case "case 31: this filesystem does not accept a non-ASCII path segment, so an NFC versus NFD pair cannot be created here"
elif [[ "$norm31_kind" == "unreadable" ]]; then
  skip_case "case 31: the NFD spelling could not be created and is not the NFC directory, so the volume's normalization property is unknown"
elif [[ "$norm31_kind" == "normalizing" ]]; then
  bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
    --out "$NORM31/$NFD_NAME/feat-x" --scan-dir "$NORM31/$NFC_NAME/feat-x" \
    --memory-root "$NORM31" >/dev/null 2>&1
  assert_eq "case 31: a normalizing volume refuses an absent NFC versus NFD pair" "3" "$?"
  assert_eq "case 31: the NFD stub home was never created" "0" \
    "$(path_exists "$NORM31/$NFD_NAME")"
  assert_eq "case 31: the NFC scan directory was never created" "0" \
    "$(path_exists "$NORM31/$NFC_NAME")"
  norm31_left=0
  for f in "$NORM31"/*; do
    [[ -e "$f" ]] && norm31_left=$((norm31_left + 1))
  done
  assert_eq "case 31: the refused run left nothing under the root" "0" "$norm31_left"
else
  skip_case "case 31: no normalization-folding volume on this runner, so the exit-3 refusal arm (probe -> VOLUME_NORMALIZES=1 -> NFC -> may_be_within) is not executed here"
  bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
    --out "$NORM31/$NFD_NAME/feat-x" --scan-dir "$NORM31/$NFC_NAME/feat-x" \
    --memory-root "$NORM31" >/dev/null 2>&1
  assert_eq "case 31: a byte-exact volume writes an absent NFC versus NFD pair" "0" "$?"
  assert_eq "case 31: the NFD home received stubs" "7" "$(count_files "$NORM31/$NFD_NAME/feat-x")"
  assert_eq "case 31: the NFC scan directory was never created" "0" \
    "$(path_exists "$NORM31/$NFC_NAME")"
  # Existing siblings the NFC step would collapse on a normalizing volume
  # must still be two directories here. Pre-create both, then write into the
  # NFD sibling while the NFC directory is the scan dir.
  NORM31B="$TEST_TMPDIR/norm31-existing"
  mkdir -p -- "$NORM31B/$NFC_NAME/feat-x" "$NORM31B/$NFD_NAME"
  if [[ -d "$NORM31B/$NFC_NAME/feat-x" && -d "$NORM31B/$NFD_NAME" ]] &&
    ! [[ "$NORM31B/$NFC_NAME" -ef "$NORM31B/$NFD_NAME" ]]; then
    cp "$FINDINGS" "$NORM31B/$NFC_NAME/feat-x/review-findings.md"
    bash "$EMIT" --findings "$NORM31B/$NFC_NAME/feat-x/review-findings.md" \
      --classes "$CLASSES" --out "$NORM31B/$NFD_NAME/feat-x/stubs" \
      --scan-dir "$NORM31B/$NFC_NAME/feat-x" >/dev/null 2>&1
    assert_eq "case 31: existing NFC and NFD siblings on a byte-exact volume still write" "0" "$?"
    assert_eq "case 31: the NFD sibling received stubs" "7" \
      "$(count_files "$NORM31B/$NFD_NAME/feat-x/stubs")"
    assert_eq "case 31: nothing landed in the NFC scan directory" "0" \
      "$(count_files "$NORM31B/$NFC_NAME/feat-x/stubs")"
  else
    skip_case "case 31: this filesystem does not keep an NFC directory and an NFD directory as distinct siblings"
  fi
fi
skip_case "case 31: the stat/diskutil fstype fallback that sends apfs and hfs to the NFC step when the probe directory is unwritable is not executed here; it needs a read-only ancestor on a real APFS or HFS Plus volume"

# The seam: EMIT_STUBS_ASSUME_NORMALIZING=1 replaces the probe verdict, so the
# NFC fold and the fence refusal run on any runner. This proves the fold and
# may_be_within honor a normalizing verdict for an absent NFC versus NFD pair.
# It does not prove what a real APFS or HFS Plus volume reports.
NORM31C="$TEST_TMPDIR/norm31-forced"
mkdir -p "$NORM31C"
env EMIT_STUBS_ASSUME_NORMALIZING=1 bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
  --out "$NORM31C/$NFD_NAME/feat-x" --scan-dir "$NORM31C/$NFC_NAME/feat-x" \
  --memory-root "$NORM31C" >/dev/null 2>&1
assert_eq "case 31: a forced normalizing verdict refuses an absent NFC versus NFD pair" "3" "$?"
assert_eq "case 31: the forced refusal created neither spelling" "0" \
  "$(path_exists "$NORM31C/$NFD_NAME" "$NORM31C/$NFC_NAME")"

# --- Case 32: each rung maps to its earliest stage ---------------------------
#
# Expected stages are the fixed table in context/stub-shape.md, not values read
# back from the writer. Case 1's stubs cover seven rungs; make-impossible gets
# its own run.
for pair in 01:edit 02:build 03:build 04:commit 05:test 06:tool-call 07:review; do
  rank="${pair%%:*}"
  stage="${pair#*:}"
  assert_contains "case 32: rank $rank stub carries earliest-stage $stage" \
    "$(cat "$OUT1"/"$rank"-*.md)" "earliest-stage: $stage"
done
OUT32="$TEST_TMPDIR/out32"
printf '1\tinvalid-state\tjudgment\tmake-impossible\t/architecture:improve\n' |
  bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT32" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 32: a make-impossible row exits 0" "0" "$?"
assert_contains "case 32: make-impossible maps to the design stage" \
  "$(cat "$OUT32"/01-*.md)" "earliest-stage: design"

# --- Case 33: the sixth field is the error text ------------------------------
OUT33="$TEST_TMPDIR/out33"
{
  printf '1\tstyle\tjudgment\teditorconfig-severity\tin-repo .editorconfig\tIDE0055: run dotnet format to apply the brace rule from .editorconfig\n'
  grep -v '^1	' "$CLASSES"
} >"$TEST_TMPDIR/classes-six.tsv"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT33" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-six.tsv" >/dev/null 2>&1
assert_eq "case 33: a six-field row exits 0" "0" "$?"
assert_eq "case 33: every row still gets its stub" "7" "$(count_files "$OUT33")"
stub33="$(cat "$OUT33"/01-*.md)"
assert_contains "case 33: the six-field stub has an Error text section" "$stub33" $'\n## Error text\n'
assert_contains "case 33: the error text is rendered on its own line" "$stub33" \
  $'\nIDE0055: run dotnet format to apply the brace rule from .editorconfig\n'
assert_contains "case 33: the six-field stub keeps its earliest stage" "$stub33" "earliest-stage: edit"
assert_contains "case 33: a five-field row renders none proposed" \
  "$(cat "$OUT33"/02-*.md)" $'## Error text\n\nnone proposed\n'

# --- Case 34: a row with the wrong field count is refused whole --------------
#
# A tab inside the error text makes seven fields; a newline inside it leaves a
# continuation line with one field, even when that line starts with a digit
# that reads like a rank.
OUT34="$TEST_TMPDIR/out34"
printf '1\tstyle\tjudgment\teditorconfig-severity\tin-repo .editorconfig\tuse\ttabs\n' >"$TEST_TMPDIR/classes-seven.tsv"
seven_err="$(bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT34" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-seven.tsv" 2>&1 >/dev/null)"
assert_eq "case 34: a seven-field row exits 2" "2" "$?"
assert_eq "case 34: a seven-field row writes nothing" "0" "$(path_exists "$OUT34")"
assert_contains "case 34: the refusal names the line" "$seven_err" "line 1"
assert_contains "case 34: the refusal names the field count" "$seven_err" "7 fields"

{
  printf '1\tstyle\tjudgment\teditorconfig-severity\tin-repo .editorconfig\tThe client gets a 404 here\n'
  printf '404 means the endpoint is gone\n'
} >"$TEST_TMPDIR/classes-cont.tsv"
cont_err="$(bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT34" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-cont.tsv" 2>&1 >/dev/null)"
assert_eq "case 34: a digit-led continuation line exits 2" "2" "$?"
assert_eq "case 34: a digit-led continuation line writes nothing" "0" "$(path_exists "$OUT34")"
assert_contains "case 34: the refusal names the continuation line" "$cont_err" "line 2"
assert_contains "case 34: the continuation line is refused for its field count" "$cont_err" "1 field"

# A continuation line whose digit IS a rank in the table must not pass as a row.
{
  printf '1\tstyle\tjudgment\teditorconfig-severity\tin-repo .editorconfig\tSee rule\n'
  printf '7 more lines follow\n'
} >"$TEST_TMPDIR/classes-cont7.tsv"
bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT34" --scan-dir "$SCAN_DIR" --dry-run \
  <"$TEST_TMPDIR/classes-cont7.tsv" >/dev/null 2>&1
assert_eq "case 34: a continuation line led by a table rank exits 2, dry run too" "2" "$?"

# --- Case 35: an empty middle field keeps its position -----------------------
OUT35="$TEST_TMPDIR/out35"
printf '1\t\tjudgment\tsemgrep-rule\tsemgrep docs\tsemgrep: replace eval with a parser call\n' |
  bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT35" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 35: an empty class field exits 0" "0" "$?"
stub35="$(cat "$OUT35"/01-*.md)"
assert_contains "case 35: the empty class takes the unclassified default" "$stub35" "finding-class: unclassified"
assert_contains "case 35: the basis stays in its own position" "$stub35" "class-basis: judgment"
assert_contains "case 35: the rung did not shift into the class" "$stub35" "rung: semgrep-rule"
assert_contains "case 35: the owner did not shift" "$stub35" "owner: semgrep docs"
assert_contains "case 35: the error text did not shift" "$stub35" $'\nsemgrep: replace eval with a parser call\n'
assert_contains "case 35: the stage follows the unshifted rung" "$stub35" "earliest-stage: commit"

# --- Case 36: a forbidden marker inside the error text -----------------------
OUT36="$TEST_TMPDIR/out36"
printf '1\tstyle\tjudgment\teditorconfig-severity\tin-repo .editorconfig\t## Findings\n' |
  bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT36" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 36: a marker in the error text exits 4" "4" "$?"
assert_eq "case 36: the marker run left no stub" "0" "$(count_files "$OUT36")"

# --- Case 37: dry run with six fields prints paths and writes nothing --------
OUT37="$TEST_TMPDIR/out37"
dry6="$(bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT37" --scan-dir "$SCAN_DIR" --dry-run \
  <"$TEST_TMPDIR/classes-six.tsv" 2>&1)"
assert_eq "case 37: a six-field dry run exits 0" "0" "$?"
assert_eq "case 37: a six-field dry run writes nothing" "0" "$(path_exists "$OUT37")"
assert_contains "case 37: a six-field dry run plans the stub path" "$dry6" "$OUT37/01-editorconfig-severity-"
assert_not_contains "case 37: a dry run prints no stub body" "$dry6" "Error text"

# --- Case 38: a command substitution in the rank field is never run ----------
#
# The first field is looked up as an associative-array key. bash 5.1 expands
# some subscripts twice; BASH_COMPAT=51 reproduces that, so a lookup that
# reached an arithmetic or -v context would create the marker file.
PWNED="$TEST_TMPDIR/pwned38"
printf '%s\tstyle\tjudgment\thook\tnone\n' "\$(touch $PWNED)" >"$TEST_TMPDIR/classes-inject.tsv"
env BASH_COMPAT=51 bash "$EMIT" --findings "$FINDINGS" --classes - --out "$TEST_TMPDIR/out38" \
  --scan-dir "$SCAN_DIR" <"$TEST_TMPDIR/classes-inject.tsv" >/dev/null 2>&1
assert_eq "case 38: a substitution-shaped rank exits 2" "2" "$?"
assert_eq "case 38: the substitution never ran" "0" "$(path_exists "$PWNED")"

# --- Case 39: a rung outside the closed set is refused whole -----------------
#
# The closed set is the rung table in context/stub-shape.md. A known rung still
# writes; anything else exits 2 before any stub is written.
OUT39="$TEST_TMPDIR/out39"
printf '1\tstyle\tjudgment\thook\tnone\n' |
  bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT39" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 39: a known rung exits 0" "0" "$?"
assert_contains "case 39: a known rung keeps its stage" "$(cat "$OUT39"/01-*.md)" "earliest-stage: tool-call"

OUT39B="$TEST_TMPDIR/out39b"
{
  grep -v '^7	' "$CLASSES"
  printf '7\tstyle\tjudgment\tlinter\tnone\n'
} >"$TEST_TMPDIR/classes-badrung.tsv"
rung_err="$(bash "$EMIT" --findings "$FINDINGS" --classes - --out "$OUT39B" --scan-dir "$SCAN_DIR" \
  <"$TEST_TMPDIR/classes-badrung.tsv" 2>&1 >/dev/null)"
assert_eq "case 39: an unknown rung exits 2" "2" "$?"
assert_eq "case 39: an unknown rung writes nothing, not even the valid rows" "0" "$(path_exists "$OUT39B")"
assert_contains "case 39: the refusal names the TSV line" "$rung_err" "line 7"
assert_contains "case 39: the refusal names the rung last" "$rung_err" "Rung: linter"
assert_not_contains "case 39: no unmapped stage is offered" "$rung_err" "unmapped"

printf '1\tstyle\tjudgment\t*\tnone\n' |
  bash "$EMIT" --findings "$FINDINGS" --classes - --out "$TEST_TMPDIR/out39c" --scan-dir "$SCAN_DIR" >/dev/null 2>&1
assert_eq "case 39: a glob-shaped rung exits 2" "2" "$?"
assert_eq "case 39: a glob-shaped rung writes nothing" "0" "$(path_exists "$TEST_TMPDIR/out39c")"

# A substitution in the rung field is compared as text under the bash 5.1
# double-expansion rules, never run.
PWNED39="$TEST_TMPDIR/pwned39"
printf '1\tstyle\tjudgment\t%s\tnone\n' "\$(touch $PWNED39)" >"$TEST_TMPDIR/classes-rung-inject.tsv"
env BASH_COMPAT=51 bash "$EMIT" --findings "$FINDINGS" --classes - --out "$TEST_TMPDIR/out39d" \
  --scan-dir "$SCAN_DIR" <"$TEST_TMPDIR/classes-rung-inject.tsv" >/dev/null 2>&1
assert_eq "case 39: a substitution-shaped rung exits 2" "2" "$?"
assert_eq "case 39: the rung substitution never ran" "0" "$(path_exists "$PWNED39")"
assert_eq "case 39: a substitution-shaped rung writes nothing" "0" "$(path_exists "$TEST_TMPDIR/out39d")"

# A newline inside the rung splits the row, so the field-count guard refuses it.
printf '1\tstyle\tjudgment\tho\nok\tnone\n' >"$TEST_TMPDIR/classes-rung-newline.tsv"
env BASH_COMPAT=51 bash "$EMIT" --findings "$FINDINGS" --classes - --out "$TEST_TMPDIR/out39e" \
  --scan-dir "$SCAN_DIR" <"$TEST_TMPDIR/classes-rung-newline.tsv" >/dev/null 2>&1
assert_eq "case 39: a rung holding a newline exits 2" "2" "$?"
assert_eq "case 39: a rung holding a newline writes nothing" "0" "$(path_exists "$TEST_TMPDIR/out39e")"

# --- Dry run ------------------------------------------------------------------

OUTDRY="$TEST_TMPDIR/outdry"
dry_out="$(bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" --out "$OUTDRY" --scan-dir "$SCAN_DIR" --dry-run 2>&1)"
assert_eq "dry run: exits 0" "0" "$?"
assert_eq "dry run: wrote nothing" "0" "$(path_exists "$OUTDRY")"
assert_contains "dry run: printed a planned filename" "$dry_out" "01-editorconfig-severity-"

# A non-ASCII home makes the fence run the normalization probe inside the
# deepest existing ancestor. The probe directory must be gone afterwards, and a
# dry run must still write nothing.
DRYU="$TEST_TMPDIR/dry-unicode"
if mkdir -p "$DRYU/probe-réviews" 2>/dev/null && [[ -d "$DRYU/probe-réviews" ]]; then
  rmdir -- "$DRYU/probe-réviews"
  dryu_out="$(bash "$EMIT" --findings "$FINDINGS" --classes "$CLASSES" \
    --out "$DRYU/stubs-é/feat-x" --scan-dir "$DRYU/réviews/feat-x" --dry-run 2>&1)"
  assert_eq "dry run: a non-ASCII home exits 0" "0" "$?"
  assert_contains "dry run: a non-ASCII home plans a filename" "$dryu_out" "01-editorconfig-severity-"
  dryu_left=0
  for f in "$DRYU"/* "$DRYU"/.[!.]*; do
    [[ -e "$f" ]] && dryu_left=$((dryu_left + 1))
  done
  assert_eq "dry run: a non-ASCII home leaves no probe directory and writes nothing" "0" "$dryu_left"
else
  skip_case "dry run: this filesystem does not accept a non-ASCII path segment"
fi

# --- Final report --------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed (%d skipped).\n' "$CASE_NUM" "$SKIPPED"
  exit 0
fi
printf '\n%d/%d checks failed (%d skipped).\n' "$FAILED" "$CASE_NUM" "$SKIPPED" >&2
exit 1
