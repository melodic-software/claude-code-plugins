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
EXPECTED_CASES=72

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
assert_eq "plan: digest is 64 hex characters" "$(digest_of "$out" 01 | grep -cE '^[0-9a-f]{64}$')" "1"
assert_eq "plan: a paths sidecar lists each file's absolute path in list order" \
  "$(lines "$P/batches/batch-01.paths")" "$P/a.md $P/b.md "
mkdir -p "$P/none"
st="$(bash "$FANOUT" status --batches "$P/batches" --results "$P/none" 2>&1)"
assert_eq "plan: digest equals the one status prints for a missing result" \
  "$(digest_of "$st" 02)" "$(digest_of "$out" 02)"

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
for n in 01 02 03 04 05 06 07 08 09 10 11; do printf 'a.md\nb.md\n' >"$B/batch-$n.txt"; done
d="$(sha "$B/batch-01.txt")"
printf 'batch: %s\r\nfiles_reviewed: 2\r\nfiles_with_findings: 1\r\n\r\n## a.md\r\n' "$d" >"$RS/rubric-batch-01.md"
printf 'batch: %s\nfiles_reviewed: 2\n' "0000" >"$RS/rubric-batch-03.md"
printf 'batch: %s\nfiles_reviewed: 3\n' "$d" >"$RS/rubric-batch-04.md"
printf 'batch: %s\nfiles_reviewed: 2\n\n## a.md\n## other.md\n' "$d" >"$RS/rubric-batch-05.md"
printf 'batch: %s\nfiles_reviewed: 2\n\n## a.md\n' "$d" >"$RS/rubric-batch-06.md"
printf 'batch: %s\nfiles_reviewed: 2\nfiles_with_findings: 1\n\n## a.md\n## b.md\n' "$d" >"$RS/rubric-batch-07.md"
# Each header must appear exactly once: merge sums every line it finds.
for _ in 1 2; do printf 'batch: %s\nfiles_reviewed: 2\nfiles_with_findings: 0\n' "$d"; done >"$RS/rubric-batch-08.md"
printf 'batch: %s\nfiles_reviewed: 2\nfiles_with_findings: 0\nfiles_with_findings: 0\n' "$d" >"$RS/rubric-batch-09.md"
printf 'batch: %s\nbatch: %s\nfiles_reviewed: 2\nfiles_with_findings: 0\n' "$d" "$d" >"$RS/rubric-batch-10.md"
printf 'batch: %s\nfiles_reviewed: 2\nfiles_reviewed: 2\nfiles_with_findings: 0\n' "$d" >"$RS/rubric-batch-11.md"
out="$(bash "$FANOUT" status --batches "$B" --results "$RS" 2>&1)"
rc=$?
assert_exit "status: exit 1 when a batch is not complete" 1 "$rc"
assert_contains "status: a matching result is complete (CRLF tolerated)" "$out" "batch=01 status=complete"
assert_contains "status: no result file is missing" "$out" "batch=02 status=missing"
assert_contains "status: another list's digest is stale" "$out" "batch=03 status=stale reason=digest"
assert_contains "status: a short files_reviewed is stale" "$out" "batch=04 status=stale reason=files_reviewed"
assert_contains "status: a heading outside the list is stale" "$out" "batch=05 status=stale reason=foreign-heading"
assert_contains "status: a missing files_with_findings is stale" "$out" "batch=06 status=stale reason=files_with_findings"
assert_contains "status: files_with_findings must match the headings" "$out" "batch=07 status=stale reason=files_with_findings"
assert_contains "status: a result written twice is stale" "$out" "batch=08 status=stale reason=digest"
assert_contains "status: a duplicated files_with_findings is stale" "$out" "batch=09 status=stale reason=files_with_findings"
assert_contains "status: a duplicated batch line is stale" "$out" "batch=10 status=stale reason=digest"
assert_contains "status: a duplicated files_reviewed is stale" "$out" "batch=11 status=stale reason=files_reviewed"
assert_contains "status: a missing row carries the current digest" "$out" "batch=02 status=missing digest=$d"
assert_contains "status: a stale row carries the current digest" "$out" "batch=03 status=stale reason=digest digest=$d"
assert_not_contains "status: a complete row carries no digest" "$out" "batch=01 status=complete digest"

# A header written twice joins into one value; each must appear exactly once
# even when the joined value would match.
H="$TEST_TMPDIR/headers/batches"
HR="$TEST_TMPDIR/headers/results"
mkdir -p "$H" "$HR"
for n in 01 02 03; do
  for k in a b c d e f g h i j k; do echo "$k.md"; done >"$H/batch-$n.txt"
done
hd="$(sha "$H/batch-01.txt")"
printf 'batch: %s\nfiles_reviewed: 1\nfiles_reviewed: 1\nfiles_with_findings: 0\n' "$hd" >"$HR/rubric-batch-01.md"
{
  printf 'batch: %s\nfiles_reviewed: 11\nfiles_with_findings: 1\nfiles_with_findings: 1\n\n' "$hd"
  for k in a b c d e f g h i j k; do echo "## $k.md"; done
} >"$HR/rubric-batch-02.md"
printf 'batch: %s\nbatch: %s\nfiles_reviewed: 11\nfiles_with_findings: 0\n' "${hd:0:32}" "${hd:32}" >"$HR/rubric-batch-03.md"
out="$(bash "$FANOUT" status --batches "$H" --results "$HR" 2>&1)"
assert_contains "status: files_reviewed 1 twice over 11 files is stale" "$out" "batch=01 status=stale reason=files_reviewed"
assert_contains "status: files_with_findings 1 twice over 11 headings is stale" "$out" "batch=02 status=stale reason=files_with_findings"
assert_contains "status: a digest split across two batch lines is stale" "$out" "batch=03 status=stale reason=digest"

# --- status: a planned batch binds the listed files' contents ------------------------

C="$TEST_TMPDIR/content"
mkdir -p "$C/docs" "$C/results" "$C/away"
printf 'one two\n' >"$C/docs/x.md"
printf 'three four\n' >"$C/docs/y.md"
printf '%s\t%s\n' x.md "$C/docs/x.md" y.md "$C/docs/y.md" >"$C/targets.tsv"
out="$(bash "$FANOUT" plan --out "$C/batches" --order mtime "$C/targets.tsv" 2>&1)"
pd="$(digest_of "$out" 01)"
result() { printf 'batch: %s\nfiles_reviewed: 2\nfiles_with_findings: 0\n' "$1" >"$C/results/rubric-batch-01.md"; }
result "$pd"
out="$(bash "$FANOUT" status --batches "$C/batches" --results "$C/results" 2>&1)"
rc=$?
assert_exit "contents: a result with plan's digest exits 0" 0 "$rc"
assert_eq "contents: and reads complete" "$out" "batch=01 status=complete"
printf 'one two changed\n' >"$C/docs/x.md"
out="$(bash "$FANOUT" status --batches "$C/batches" --results "$C/results" 2>&1)"
rc=$?
assert_exit "contents: an edited listed file exits 1" 1 "$rc"
assert_contains "contents: an edited listed file is stale" "$out" "batch=01 status=stale reason=digest digest="
newd="$(digest_of "$out" 01)"
assert_eq "contents: the printed digest is a new 64-hex digest" \
  "$([[ "$newd" != "$pd" ]] && printf '%s\n' "$newd" | grep -cE '^[0-9a-f]{64}$')" "1"
result "$newd"
out="$(bash "$FANOUT" status --batches "$C/batches" --results "$C/results" 2>&1)"
assert_eq "contents: a result carrying the printed digest is complete" "$out" "batch=01 status=complete"
bash "$FANOUT" merge --batches "$C/batches" --results "$C/results" --out "$C/merged.md" >/dev/null 2>&1
rc=$?
assert_exit "contents: merge accepts a complete planned set" 0 "$rc"
mv "$C/docs/y.md" "$C/away/y.md"
out="$(bash "$FANOUT" status --batches "$C/batches" --results "$C/results" 2>&1)"
assert_contains "contents: a listed file moved away is stale" "$out" "batch=01 status=stale reason=paths digest="
again="$(bash "$FANOUT" status --batches "$C/batches" --results "$C/results" 2>&1)"
assert_eq "contents: the digest without that file is deterministic" "$again" "$out"
mv "$C/away/y.md" "$C/docs/y.md"
out="$(bash "$FANOUT" status --batches "$C/batches" --results "$C/results" 2>&1)"
assert_eq "contents: restoring the file reads complete again" "$out" "batch=01 status=complete"

# --- plan: sidecar path resolution ------------------------------------------------

# A relative path resolves against the plan's cwd, never through CDPATH.
RP="$TEST_TMPDIR/relpaths"
mkdir -p "$RP/proj/docs" "$RP/decoy/docs" "$RP/results" "$RP/elsewhere"
printf 'one two\n' >"$RP/proj/docs/x.md"
printf 'x.md\tdocs/x.md\n' >"$RP/targets.tsv"
out="$(cd "$RP/proj" && CDPATH="$RP/decoy" bash "$FANOUT" plan --out "$RP/batches" --order mtime "$RP/targets.tsv" 2>&1)"
assert_eq "paths: a relative path ignores CDPATH and gets one sidecar line" \
  "$(cat "$RP/batches/batch-01.paths")" "$(cd -P "$RP/proj/docs" && pwd)/x.md"
printf 'batch: %s\nfiles_reviewed: 1\nfiles_with_findings: 0\n' "$(digest_of "$out" 01)" >"$RP/results/rubric-batch-01.md"
out="$(cd "$RP/elsewhere" && bash "$FANOUT" status --batches "$RP/batches" --results "$RP/results" 2>&1)"
assert_eq "paths: status from another cwd still reads a relative plan complete" "$out" "batch=01 status=complete"

# An absolute path in Windows form is kept as given.
if command -v cygpath >/dev/null 2>&1; then
  WP="$TEST_TMPDIR/winpaths"
  mkdir -p "$WP/docs" "$WP/results"
  printf 'one two\n' >"$WP/docs/x.md"
  wx="$(cygpath -m "$WP/docs/x.md")"
  printf 'x.md\t%s\n' "$wx" >"$WP/targets.tsv"
  out="$(bash "$FANOUT" plan --out "$WP/batches" --order mtime "$WP/targets.tsv" 2>&1)"
  assert_eq "paths: a C:/ absolute path is kept unchanged" "$(cat "$WP/batches/batch-01.paths")" "$wx"
  printf 'batch: %s\nfiles_reviewed: 1\nfiles_with_findings: 0\n' "$(digest_of "$out" 01)" >"$WP/results/rubric-batch-01.md"
  out="$(bash "$FANOUT" status --batches "$WP/batches" --results "$WP/results" 2>&1)"
  assert_eq "paths: a C:/ path plan reads complete" "$out" "batch=01 status=complete"
else
  skip "paths: a C:/ absolute path is kept unchanged" "no cygpath"
  skip "paths: a C:/ path plan reads complete" "no cygpath"
fi

# A listed file plan cannot read is named on stderr.
UP="$TEST_TMPDIR/unreadable"
mkdir -p "$UP"
printf 'gone.md\t%s\n' "$UP/gone.md" >"$UP/targets.tsv"
out="$(bash "$FANOUT" plan --out "$UP/batches" --order mtime "$UP/targets.tsv" 2>&1 >/dev/null)"
assert_contains "paths: plan warns about a sidecar path it cannot read" "$out" "sidecar path unreadable: $UP/gone.md"

# A sidecar whose length differs from the list's is stale; a sidecar makes the
# digest differ from the list-only one even when no listed file is readable.
SP="$TEST_TMPDIR/sidecar"
mkdir -p "$SP/batches" "$SP/results"
printf 'a.md\nb.md\n' >"$SP/batches/batch-01.txt"
printf '%s\n' "$SP/nowhere/a.md" >"$SP/batches/batch-01.paths"
printf 'a.md\nb.md\n' >"$SP/batches/batch-02.txt"
printf '%s\n' "$SP/nowhere/a.md" "$SP/nowhere/b.md" >"$SP/batches/batch-02.paths"
printf 'batch: x\nfiles_reviewed: 2\nfiles_with_findings: 0\n' >"$SP/results/rubric-batch-01.md"
out="$(bash "$FANOUT" status --batches "$SP/batches" --results "$SP/results" 2>&1)"
assert_contains "sidecar: a length mismatch with the list is stale" "$out" "batch=01 status=stale reason=paths digest="
newd="$(digest_of "$out" 02)"
assert_eq "sidecar: every listed file missing still differs from the list-only digest" \
  "$([[ -n "$newd" && "$newd" != "$(sha "$SP/batches/batch-02.txt")" ]] && echo differs)" "differs"

# A tree moved after plan leaves every sidecar path unreadable: stale, and a
# result carrying the printed digest cannot make it complete.
RL="$TEST_TMPDIR/relocate"
mkdir -p "$RL/A/docs" "$RL/results"
printf 'one two\n' >"$RL/A/docs/x.md"
printf 'x.md\t%s\n' "$RL/A/docs/x.md" >"$RL/targets.tsv"
bash "$FANOUT" plan --out "$RL/batches" --order mtime "$RL/targets.tsv" >/dev/null 2>&1
mv "$RL/A" "$RL/B"
out="$(bash "$FANOUT" status --batches "$RL/batches" --results "$RL/results" 2>&1)"
printf 'batch: %s\nfiles_reviewed: 1\nfiles_with_findings: 0\n' "$(digest_of "$out" 01)" >"$RL/results/rubric-batch-01.md"
out="$(bash "$FANOUT" status --batches "$RL/batches" --results "$RL/results" 2>&1)"
assert_contains "sidecar: a relocated tree is stale reason=paths" "$out" "batch=01 status=stale reason=paths digest="
printf 'edited\n' >>"$RL/B/docs/x.md"
out="$(bash "$FANOUT" status --batches "$RL/batches" --results "$RL/results" 2>&1)"
assert_contains "sidecar: and stays stale after an edit in the new tree" "$out" "batch=01 status=stale reason=paths digest="

# A sidecar rewritten with CRLF endings resolves to the same paths.
CL="$TEST_TMPDIR/crlf"
mkdir -p "$CL/docs" "$CL/results"
printf 'one two\n' >"$CL/docs/x.md"
printf 'x.md\t%s\n' "$CL/docs/x.md" >"$CL/targets.tsv"
out="$(bash "$FANOUT" plan --out "$CL/batches" --order mtime "$CL/targets.tsv" 2>&1)"
pd="$(digest_of "$out" 01)"
printf '%s\r\n' "$(cat "$CL/batches/batch-01.paths")" >"$CL/batches/batch-01.paths"
out="$(bash "$FANOUT" status --batches "$CL/batches" --results "$CL/results" 2>&1)"
assert_eq "sidecar: a CRLF sidecar gives plan's digest" "$(digest_of "$out" 01)" "$pd"
printf 'batch: %s\nfiles_reviewed: 1\nfiles_with_findings: 0\n' "$pd" >"$CL/results/rubric-batch-01.md"
out="$(bash "$FANOUT" status --batches "$CL/batches" --results "$CL/results" 2>&1)"
assert_eq "sidecar: a CRLF sidecar reads complete" "$out" "batch=01 status=complete"
printf 'edited\n' >>"$CL/docs/x.md"
out="$(bash "$FANOUT" status --batches "$CL/batches" --results "$CL/results" 2>&1)"
assert_contains "sidecar: a CRLF sidecar still detects an edit" "$out" "batch=01 status=stale reason=digest digest="

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
