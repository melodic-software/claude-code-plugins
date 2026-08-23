#!/usr/bin/env bash
# Self-contained tests for emit-findings.sh (no external test lib — ships with
# the plugin; fixtures are built inline in a tmpdir).
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SCRIPT_DIR/emit-findings.sh"
DETECT="$SCRIPT_DIR/detect.sh"
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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
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

# --- Fixture repo ---------------------------------------------------------------------

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
(
  cd "$REPO" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name Test
  git checkout -q -b test-branch
)

TARGET="$REPO/doc.md"
cat >"$TARGET" <<'EOF'
---
description: "Fixture doc. Use when: 'sweep the fixture corpus'."
---

# Fixture

Do not use markdown in your response.

Never run 'sweep the fixture corpus' against an unreviewed corpus.

Report the pipe | character carefully.
EOF

# --- Usage / refusal paths ------------------------------------------------------------

bash "$EMIT" >/dev/null 2>&1
assert_exit "no args exits 2" 2 "$?"

bash "$EMIT" --from /nonexistent --out "$TEST_TMPDIR/x.md" >/dev/null 2>&1
assert_exit "missing --from file exits 2" 2 "$?"

NOTSCAN="$TEST_TMPDIR/notscan.txt"
printf 'this is not detector output\n' >"$NOTSCAN"
(cd "$REPO" && bash "$EMIT" --from "$NOTSCAN" --out "$TEST_TMPDIR/y.md") >/dev/null 2>&1
assert_exit "input with no detect blocks exits 3" 3 "$?"

BLOCKS="$TEST_TMPDIR/blocks.txt"
{
  printf 'File: %s\n' "$TARGET"
  printf 'Finding tier: 2\nFinding shape: negation\nFinding line: 7\n'
  printf 'Finding excerpt: Do not use markdown in your response.\n---\n'
} >"$BLOCKS"
(cd "$REPO" && bash "$EMIT" --from "$BLOCKS" --out "$TEST_TMPDIR/z.md" --branch '') >/dev/null 2>&1
assert_exit "empty --branch value exits 2" 2 "$?"

(cd "$REPO" && bash "$EMIT" --from "$BLOCKS" --out "$TEST_TMPDIR/z.md" --declined-carveout notanint) >/dev/null 2>&1
assert_exit "non-integer --declined-carveout exits 2" 2 "$?"

# --- Happy path: a real detect.sh run through the writer -------------------------------

DETOUT="$TEST_TMPDIR/detout.txt"
(cd "$REPO" && bash "$DETECT" doc.md) >"$DETOUT"
OUT1="$TEST_TMPDIR/out/findings.md"
(cd "$REPO" && bash "$EMIT" --from "$DETOUT" --out "$OUT1") >/dev/null
body="$(cat "$OUT1")"

assert_contains "declares the consumed type" "$body" "type: review-findings"
assert_contains "carries the current branch" "$body" "branch: test-branch"
assert_contains "leads the Finding cell with the qualified rule id" "$body" \
  "docs-hygiene/audit-noise/rule-negation-without-positive"
assert_contains "tier is looked up as IMPORTANT" "$body" "| IMPORTANT | high |"
assert_contains "Surface(s) names the producer" "$body" "docs-hygiene:audit-noise"
assert_contains "Location is repo-relative" "$body" "| doc.md:7 |"
assert_not_contains "Location is never absolute" "$body" "$REPO/doc.md"
assert_contains "carries the fired prohibition in the run own values" "$body" 'prohibition="do not"'

# The quoted-trigger fence: line 9 quotes a phrase from the file's description.
assert_not_contains "a row quoting a trigger phrase never reaches the relay" "$body" "doc.md:9"
assert_contains "and its decline is counted, never silent" "$body" \
  "reason=quoted-trigger-phrase (body-scope fence)"

# --- Body-scope fence is recomputed, not trusted from the caller -----------------------

FORGED="$TEST_TMPDIR/forged.txt"
{
  printf 'File: %s\n' "$TARGET"
  printf 'Finding tier: 2\nFinding shape: negation\nFinding line: 2\n'
  printf 'Finding excerpt: forged frontmatter row\n---\n'
} >"$FORGED"
OUT2="$TEST_TMPDIR/out/forged.md"
(cd "$REPO" && bash "$EMIT" --from "$FORGED" --out "$OUT2") >/dev/null
forged_body="$(cat "$OUT2")"
assert_not_contains "a forged frontmatter row is refused by the writer fence" "$forged_body" "doc.md:2"
assert_contains "and counted as a frontmatter decline" "$forged_body" "reason=frontmatter (body-scope fence)"

# --- Only the crosswalk-carrying shape is emitted --------------------------------------

OTHER="$TEST_TMPDIR/other.txt"
{
  printf 'File: %s\n' "$TARGET"
  printf 'Finding tier: 1\nFinding shape: citation\nFinding line: 7\n'
  printf 'Finding excerpt: a citation row\n---\n'
} >"$OTHER"
OUT3="$TEST_TMPDIR/out/other.md"
(cd "$REPO" && bash "$EMIT" --from "$OTHER" --out "$OUT3") >/dev/null
other_body="$(cat "$OUT3")"
assert_contains "a shape with no crosswalk row is declined" "$other_body" \
  "citation count=1 reason=no-severity-crosswalk-row"
assert_contains "zero emittable findings still writes the file" "$other_body" "## Findings"
assert_contains "and says the rule returned no result" "$other_body" \
  "Returned no result: [docs-hygiene/audit-noise/rule-negation-without-positive]"

# --- Out-of-repo fence -----------------------------------------------------------------

OUTSIDE="$TEST_TMPDIR/outside.md"
cat >"$OUTSIDE" <<'EOF'
# Outside the repo

Do not use markdown in your response.
EOF
OOR="$TEST_TMPDIR/oor.txt"
{
  printf 'File: %s\n' "$OUTSIDE"
  printf 'Finding tier: 2\nFinding shape: negation\nFinding line: 3\n'
  printf 'Finding excerpt: Do not use markdown in your response.\n---\n'
} >"$OOR"
OUT4="$TEST_TMPDIR/out/oor.md"
(cd "$REPO" && bash "$EMIT" --from "$OOR" --out "$OUT4") >/dev/null
oor_body="$(cat "$OUT4")"
assert_contains "a path outside the repo root is declined" "$oor_body" "reason=outside-repo-root"

# --- Non-overwrite naming --------------------------------------------------------------

(cd "$REPO" && bash "$EMIT" --from "$DETOUT" --out "$OUT1") >/dev/null
if [[ -f "${OUT1%.md}-2.md" ]]; then
  pass "a colliding --out takes the -2 suffix rather than clobbering"
else
  fail "a colliding --out takes the -2 suffix rather than clobbering" "${OUT1%.md}-2.md exists" "absent"
fi

# --- Out-of-repo fence: a traversing path is fail-closed --------------------------------

# The prefix test is lexical, so `/repo/../x.md` starts with `/repo/` while
# resolving outside it. A `..` segment must decline rather than emit a row whose
# Location traverses out of the working tree.
TRAVERSE="$TEST_TMPDIR/traverse.txt"
{
  printf 'File: %s\n' "$REPO/../outside.md"
  printf 'Finding tier: 2\nFinding shape: negation\nFinding line: 3\n'
  printf 'Finding excerpt: Do not use markdown.\n---\n'
} >"$TRAVERSE"
OUT6="$TEST_TMPDIR/out/traverse.md"
(cd "$REPO" && bash "$EMIT" --from "$TRAVERSE" --out "$OUT6") >/dev/null
trav_body="$(cat "$OUT6")"
assert_not_contains "a traversing path never reaches the relay" "$trav_body" ".."
assert_contains "and is declined as out-of-repo" "$trav_body" "reason=outside-repo-root"

# --- branch: quoting for YAML-implicit-typed names --------------------------------------

# Git accepts `true`, `null` and `123` as branch names. Left plain, a consumer
# reads them back as a boolean/null/number and the relay's exact-string match
# never admits the file.
for bad_branch in true null 123 2026-08-23 no; do
  OUTB="$TEST_TMPDIR/out/branch-$bad_branch.md"
  (cd "$REPO" && bash "$EMIT" --from "$DETOUT" --out "$OUTB" --branch "$bad_branch") >/dev/null
  assert_contains "YAML-implicit branch '$bad_branch' is quoted" "$(cat "$OUTB")" "branch: \"$bad_branch\""
done
OUTP="$TEST_TMPDIR/out/branch-plain.md"
(cd "$REPO" && bash "$EMIT" --from "$DETOUT" --out "$OUTP" --branch "feature/ordinary-name") >/dev/null
assert_contains "an ordinary branch stays an unquoted plain scalar" "$(cat "$OUTP")" "branch: feature/ordinary-name"

# --- The fired marker is carried from the scanner ---------------------------------------

MARKER_IN="$TEST_TMPDIR/marker.txt"
{
  printf 'File: %s\n' "$TARGET"
  printf 'Finding tier: 2\nFinding shape: negation\nFinding line: 7\n'
  printf 'Finding excerpt: Never commit a secret. Do not use markdown.\n'
  printf 'Finding marker: do not\n---\n'
} >"$MARKER_IN"
OUT7="$TEST_TMPDIR/out/marker.md"
(cd "$REPO" && bash "$EMIT" --from "$MARKER_IN" --out "$OUT7") >/dev/null
assert_contains "the scanner-supplied marker wins over a whole-line scan" "$(cat "$OUT7")" 'prohibition="do not"'

# --- Counted carve-out -----------------------------------------------------------------

OUT5="$TEST_TMPDIR/out/carve.md"
(cd "$REPO" && bash "$EMIT" --from "$DETOUT" --out "$OUT5" --declined-carveout 3) >/dev/null
assert_contains "a judgment-lane drop is counted, never silent" "$(cat "$OUT5")" \
  "negation count=3 reason=judgment-lane-dismissal"

# --- Final report ----------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
