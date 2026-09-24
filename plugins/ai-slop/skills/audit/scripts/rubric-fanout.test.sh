#!/usr/bin/env bash
# Self-contained tests for rubric-fanout.sh: fixtures are built inline in a
# tmpdir, with the same git and config isolation as detect.test.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FANOUT="$SCRIPT_DIR/rubric-fanout.sh"
CATALOG="$SCRIPT_DIR/../reference/catalog.md"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

FAILED=0
CASE_NUM=0
SKIPPED=0
# PASS + FAIL + SKIP when every case runs; see detect.test.sh for the contract.
EXPECTED_CASES=37

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
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
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}

sha() { sha256sum <"$1" | cut -d' ' -f1; }
lines() { tr '\n' ' ' <"$1"; }
# digest_of <plan output> <batch>: the digest= field of that batch's row.
digest_of() { printf '%s\n' "$1" | sed -n "s/^batch=$2 .* digest=//p"; }

# --- plan: packing by word budget --------------------------------------------------

P="$TEST_TMPDIR/pack"
mkdir -p "$P"
printf 'one two three four\n' >"$P/a.md"
printf 'one two three four\n' >"$P/b.md"
for _ in 1 2 3; do printf 'w w w w w w w w w w\n'; done >"$P/big.md"
printf 'one two three\n' >"$P/c.md"
touch -t 202601040000 "$P/a.md"
touch -t 202601030000 "$P/b.md"
touch -t 202601020000 "$P/big.md"
touch -t 202601010000 "$P/c.md"
printf '%s\t%s\n' a.md "$P/a.md" b.md "$P/b.md" big.md "$P/big.md" c.md "$P/c.md" >"$P/targets.tsv"
out="$(bash "$FANOUT" plan --out "$P/batches" --budget 10 --order mtime "$P/targets.tsv" 2>&1)"
rc=$?
assert_exit "plan: exit 0" 0 "$rc"
assert_contains "plan: first batch fills to the budget" "$out" "batch=01 list=$P/batches/batch-01.txt files=2 words=8 "
assert_contains "plan: an oversize file is its own batch" "$out" "batch=02 list=$P/batches/batch-02.txt files=1 words=30 "
assert_contains "plan: the file after it starts a new batch" "$out" "batch=03 list=$P/batches/batch-03.txt files=1 words=3 "
assert_eq "plan: batch list holds keys in order" "$(lines "$P/batches/batch-01.txt")" "a.md b.md "
assert_eq "plan: oversize batch list" "$(lines "$P/batches/batch-02.txt")" "big.md "
assert_contains "plan: digest is sha256 of the list file" "$out" "files=1 words=30 digest=$(sha "$P/batches/batch-02.txt")"
assert_eq "plan: digest is 64 hex characters" "$(digest_of "$out" 01 | grep -cE '^[0-9a-f]{64}$')" "1"

# sha256sum escapes a file name holding a backslash and prefixes the hash with
# `\`, so the digest is taken from stdin.
BSL=$'\x5c'
BS="$TEST_TMPDIR/back${BSL}lash"
if mkdir "$BS" 2>/dev/null && [[ -n "$(find "$TEST_TMPDIR" -maxdepth 1 -name "back${BSL}${BSL}lash")" ]]; then
  out="$(bash "$FANOUT" plan --out "$BS" --order mtime "$P/targets.tsv" 2>&1)"
  assert_eq "plan: a backslash in --out still yields a bare 64-hex digest" \
    "$(digest_of "$out" 01 | grep -cE '^[0-9a-f]{64}$')" "1"
else
  skip "plan: a backslash in --out still yields a bare 64-hex digest" "no backslash in file names"
fi

out="$(bash "$FANOUT" plan --out "$P/batches" --budget 10 --order mtime "$P/targets.tsv" 2>&1)"
rc=$?
assert_exit "plan: refuses a directory holding batch lists" 2 "$rc"
assert_contains "plan: refusal names the resume path" "$out" "already holds batch lists"

# --- plan: mtime order, tie broken by key ---------------------------------------

M="$TEST_TMPDIR/mtime"
mkdir -p "$M"
for f in x y z; do printf 'text\n' >"$M/$f.md"; done
touch -t 202602010000 "$M/z.md" "$M/y.md"
touch -t 202603010000 "$M/x.md"
printf '%s\t%s\n' z.md "$M/z.md" y.md "$M/y.md" x.md "$M/x.md" >"$M/targets.tsv"
bash "$FANOUT" plan --out "$M/batches" --order mtime "$M/targets.tsv" >/dev/null 2>&1
assert_eq "plan mtime: newest first, a tie broken by key" "$(lines "$M/batches/batch-01.txt")" "x.md y.md z.md "

# --- plan: repo order, impact class then 90-day change count ----------------------

R="$TEST_TMPDIR/repo"
mkdir -p "$R/docs" "$R/.claude/rules"
(
  cd "$R" || exit 1
  git init -q .
  commit() { git add -A && git -c commit.gpgsign=false commit -q -m "$1"; }
  printf 'a\n' >README.md
  printf 'a\n' >docs/hot.md
  printf 'a\n' >docs/warm.md
  printf 'a\n' >docs/cold.md
  commit one
  printf 'b\n' >>docs/hot.md
  printf 'b\n' >>docs/warm.md
  commit two
  printf 'c\n' >>docs/hot.md
  commit three
  printf 'rule\n' >.claude/rules/r.md
) >/dev/null 2>&1
printf '%s\t%s\n' docs/cold.md "$R/docs/cold.md" docs/warm.md "$R/docs/warm.md" \
  docs/hot.md "$R/docs/hot.md" .claude/rules/r.md "$R/.claude/rules/r.md" \
  README.md "$R/README.md" >"$R/targets.tsv"
bash "$FANOUT" plan --out "$TEST_TMPDIR/repo-batches" --order repo "$R/targets.tsv" >/dev/null 2>&1
assert_eq "plan repo: impact class first, then change count, then key" \
  "$(lines "$TEST_TMPDIR/repo-batches/batch-01.txt")" \
  "README.md .claude/rules/r.md docs/hot.md docs/warm.md docs/cold.md "
bash "$FANOUT" plan --out "$TEST_TMPDIR/auto-batches" "$R/targets.tsv" >/dev/null 2>&1
assert_eq "plan auto: a repository target takes repo order" \
  "$(lines "$TEST_TMPDIR/auto-batches/batch-01.txt")" \
  "README.md .claude/rules/r.md docs/hot.md docs/warm.md docs/cold.md "

# Keys are relative to CLAUDE_PROJECT_DIR, which may sit below the git
# toplevel; change counts still come from each file's own repository path.
CLAUDE_PROJECT_DIR="$R/docs" bash "$SCRIPT_DIR/detect.sh" --list-targets "$R/docs" >"$TEST_TMPDIR/sub-targets.tsv" 2>/dev/null
bash "$FANOUT" plan --out "$TEST_TMPDIR/sub-batches" --order repo "$TEST_TMPDIR/sub-targets.tsv" >/dev/null 2>&1
assert_eq "plan repo: project dir below the toplevel still counts changes" \
  "$(lines "$TEST_TMPDIR/sub-batches/batch-01.txt")" "hot.md warm.md cold.md "

# --- extract ------------------------------------------------------------------------

out="$(bash "$FANOUT" extract)"
want="$(grep -c '^- v1: rubric' "$CATALOG")"
# The human-writing section is kept whole, so its own rule headings ride along.
human="$(awk '/^## / { h = ($0 ~ /^## Signs of human writing/) } h && /^### rule-/' "$CATALOG" | wc -l | tr -d ' ')"
assert_eq "extract: one rule section per catalog v1: rubric marker, plus the human-writing entries" \
  "$(printf '%s\n' "$out" | grep -c '^### rule-')" "$((want + human))"
assert_eq "extract: every marker comes through" "$(printf '%s\n' "$out" | grep -c '^- v1: rubric')" "$want"
assert_contains "extract: the human-writing section is included" "$out" "## Signs of human writing"
assert_not_contains "extract: a script rule is left out" "$out" "### rule-em-dash"
bash "$FANOUT" extract --out "$TEST_TMPDIR/rubric.md"
assert_eq "extract --out: writes the same text" "$(cat "$TEST_TMPDIR/rubric.md")" "$out"

# --- status ---------------------------------------------------------------------

B="$TEST_TMPDIR/status/batches"
RS="$TEST_TMPDIR/status/results"
mkdir -p "$B" "$RS"
for n in 01 02 03 04 05; do printf 'a.md\nb.md\n' >"$B/batch-$n.txt"; done
d="$(sha "$B/batch-01.txt")"
printf 'batch: %s\r\nfiles_reviewed: 2\r\nfiles_with_findings: 1\r\n\r\n## a.md\r\n' "$d" >"$RS/rubric-batch-01.md"
printf 'batch: %s\nfiles_reviewed: 2\n' "0000" >"$RS/rubric-batch-03.md"
printf 'batch: %s\nfiles_reviewed: 3\n' "$d" >"$RS/rubric-batch-04.md"
printf 'batch: %s\nfiles_reviewed: 2\n\n## a.md\n## other.md\n' "$d" >"$RS/rubric-batch-05.md"
out="$(bash "$FANOUT" status --batches "$B" --results "$RS" 2>&1)"
rc=$?
assert_exit "status: exit 1 when a batch is not complete" 1 "$rc"
assert_contains "status: a matching result is complete (CRLF tolerated)" "$out" "batch=01 status=complete"
assert_contains "status: no result file is missing" "$out" "batch=02 status=missing"
assert_contains "status: another list's digest is stale" "$out" "batch=03 status=stale reason=digest"
assert_contains "status: a short files_reviewed is stale" "$out" "batch=04 status=stale reason=files_reviewed"
assert_contains "status: a heading outside the list is stale" "$out" "batch=05 status=stale reason=foreign-heading"

# --- merge ----------------------------------------------------------------------

out="$(bash "$FANOUT" merge --batches "$B" --results "$RS" --out "$TEST_TMPDIR/merged-refused.md" 2>&1)"
rc=$?
assert_exit "merge: refuses while a batch is not complete" 1 "$rc"
assert_contains "merge: refusal prints the status rows" "$out" "batch=02 status=missing"
assert_eq "merge: refusal writes no file" "$([[ -e "$TEST_TMPDIR/merged-refused.md" ]] && echo present || echo absent)" "absent"

MB="$TEST_TMPDIR/merge/batches"
MR="$TEST_TMPDIR/merge/results"
mkdir -p "$MB" "$MR"
printf 'a.md\nb.md\n' >"$MB/batch-01.txt"
printf 'c.md\n' >"$MB/batch-02.txt"
cat >"$MR/rubric-batch-01.md" <<EOF
batch: $(sha "$MB/batch-01.txt")
files_reviewed: 2
files_with_findings: 1

## a.md

- L3 rule-superficial-analysis: "quote one" -- reason
- L9 rule-promotional-language: "quote two" -- reason
EOF
cat >"$MR/rubric-batch-02.md" <<EOF
batch: $(sha "$MB/batch-02.txt")
files_reviewed: 1
files_with_findings: 1

## c.md

- L1 rule-superficial-analysis: "quote three" -- reason
EOF
bash "$FANOUT" status --batches "$MB" --results "$MR" >/dev/null 2>&1
rc=$?
assert_exit "status: exit 0 when every batch is complete" 0 "$rc"
bash "$FANOUT" merge --batches "$MB" --results "$MR" --out "$TEST_TMPDIR/merged.md" >/dev/null 2>&1
rc=$?
assert_exit "merge: exit 0" 0 "$rc"
merged="$(cat "$TEST_TMPDIR/merged.md")"
assert_contains "merge: files_reviewed is summed" "$merged" "files_reviewed: 3"
assert_contains "merge: files_with_findings is summed" "$merged" "files_with_findings: 2"
assert_contains "merge: per-rule total across batches" "$merged" "rule_total: rule-superficial-analysis=2"
assert_contains "merge: per-rule total for a single hit" "$merged" "rule_total: rule-promotional-language=1"
assert_eq "merge: one files_reviewed line, the summed one" "$(grep -c '^files_reviewed:' "$TEST_TMPDIR/merged.md")" "1"
assert_eq "merge: bodies in batch order" "$(grep '^## ' "$TEST_TMPDIR/merged.md" | tr '\n' ' ')" "## a.md ## c.md "

# --- Result ---------------------------------------------------------------------

echo
TOTAL=$((CASE_NUM + SKIPPED))
RC=0
if [[ "$TOTAL" -ne "$EXPECTED_CASES" ]]; then
  RC=1
  printf 'CASE COUNT MISMATCH: ran %d cases (%d pass/fail + %d host skip), expected %d.\n' \
    "$TOTAL" "$CASE_NUM" "$SKIPPED" "$EXPECTED_CASES" >&2
fi
if [[ "$FAILED" -ne 0 ]]; then
  RC=1
  echo "$FAILED of $CASE_NUM cases FAILED, $SKIPPED host skip(s)"
elif [[ "$RC" -eq 0 ]]; then
  echo "All $CASE_NUM cases passed, $SKIPPED host skip(s)"
fi
exit "$RC"
