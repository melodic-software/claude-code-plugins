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
TEST_TMPDIR="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 2; }
[[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]] || { echo "mktemp gave no directory: $TEST_TMPDIR" >&2; exit 2; }
trap 'rm -rf "$TEST_TMPDIR"' EXIT
export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

FAILED=0
CASE_NUM=0
SKIPPED=0
# PASS + FAIL + SKIP when every case runs; see detect.test.sh for the contract.
EXPECTED_CASES=169

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
# assert_line_in <name> <file> <line>: the file holds that exact line.
assert_line_in() {
  if grep -qxF -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1" "line: $3" "$(cat "$2" 2>&1)"; fi
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
assert_contains "extract: the saturation clause names the saturated decline" "$out" "reason=saturated"
assert_contains "extract: and the cap decline" "$out" "reason=cap"
assert_contains "extract: the U+26A0 counter-sign ruling rides along" "$out" "U+26A0"
# shellcheck disable=SC2016  # literal backticks, not a command substitution
assert_contains "extract: the terse rule: reason ruling rides along" "$out" 'A terse `rule: reason` line'
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
  printf 'one load-bearing\n' >"$WP/docs/x.md"
  wx="$(cygpath -m "$WP/docs/x.md")"
  printf 'x.md\t%s\n' "$wx" >"$WP/targets.tsv"
  out="$(bash "$FANOUT" plan --out "$WP/batches" --order mtime "$WP/targets.tsv" 2>&1)"
  assert_eq "paths: a C:/ absolute path is kept unchanged" "$(cat "$WP/batches/batch-01.paths")" "$wx"
  assert_line_in "paths: cues.txt counts a C:/ path's cue" "$WP/batches/cues.txt" \
    "cue=load-bearing occurrences=1 files=1 saturated=no"
  printf 'batch: %s\nfiles_reviewed: 1\nfiles_with_findings: 0\n' "$(digest_of "$out" 01)" >"$WP/results/rubric-batch-01.md"
  out="$(bash "$FANOUT" status --batches "$WP/batches" --results "$WP/results" 2>&1)"
  assert_eq "paths: a C:/ path plan reads complete" "$out" "batch=01 status=complete"
else
  skip "paths: a C:/ absolute path is kept unchanged" "no cygpath"
  skip "paths: cues.txt counts a C:/ path's cue" "no cygpath"
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

# A directory where a listed file stood is not a readable file.
DR="$TEST_TMPDIR/dirpath"
mkdir -p "$DR/docs" "$DR/results"
printf 'one\n' >"$DR/docs/x.md"
printf 'x.md\t%s\n' "$DR/docs/x.md" >"$DR/targets.tsv"
bash "$FANOUT" plan --out "$DR/batches" --order mtime "$DR/targets.tsv" >/dev/null 2>&1
mv "$DR/docs/x.md" "$DR/x.md.moved"
mkdir "$DR/docs/x.md"
out="$(bash "$FANOUT" status --batches "$DR/batches" --results "$DR/results" 2>&1)"
printf 'batch: %s\nfiles_reviewed: 1\nfiles_with_findings: 0\n' "$(digest_of "$out" 01)" >"$DR/results/rubric-batch-01.md"
out="$(bash "$FANOUT" status --batches "$DR/batches" --results "$DR/results" 2>&1)"
assert_contains "sidecar: a directory at a listed path is stale reason=paths" "$out" "batch=01 status=stale reason=paths digest="

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

# A missing result whose sidecar cannot bind the contents says reason=paths;
# one whose sidecar is sound keeps the plain missing row.
MS="$TEST_TMPDIR/missing-sidecar"
mkdir -p "$MS/docs" "$MS/results" "$MS/bad"
printf 'one two\n' >"$MS/docs/x.md"
printf 'x.md\t%s\n' "$MS/docs/x.md" >"$MS/targets.tsv"
out="$(bash "$FANOUT" plan --out "$MS/batches" --order mtime "$MS/targets.tsv" 2>&1)"
pd="$(digest_of "$out" 01)"
out="$(bash "$FANOUT" status --batches "$MS/batches" --results "$MS/results" 2>&1)"
assert_eq "missing: a sound sidecar keeps the plain missing row" "$out" "batch=01 status=missing digest=$pd"
printf 'a.md\nb.md\n' >"$MS/bad/batch-01.txt"
printf '%s\n' "$MS/docs/x.md" >"$MS/bad/batch-01.paths"
printf 'a.md\n' >"$MS/bad/batch-02.txt"
printf '%s\n' "$MS/nowhere/a.md" >"$MS/bad/batch-02.paths"
out="$(bash "$FANOUT" status --batches "$MS/bad" --results "$MS/results" 2>&1)"
assert_contains "missing: a sidecar length mismatch says reason=paths" "$out" "batch=01 status=missing reason=paths digest="
assert_contains "missing: an all-missing sidecar says reason=paths" "$out" "batch=02 status=missing reason=paths digest="

# The digest, computed here without batch_digest: the list, the separator
# line, then sha256sum over the regular file only; the missing and directory
# entries add nothing.
MX="$TEST_TMPDIR/mixed"
mkdir -p "$MX/b" "$MX/results" "$MX/docs/d.md"
printf 'one\n' >"$MX/docs/r.md"
printf 'r.md\nm.md\nd.md\n' >"$MX/b/batch-01.txt"
printf '%s\n' "$MX/docs/r.md" "$MX/docs/m.md" "$MX/docs/d.md" >"$MX/b/batch-01.paths"
want="$({ cat "$MX/b/batch-01.txt"; printf -- '--- rubric-fanout batch contents ---\n'; sha256sum -- "$MX/docs/r.md"; } | sha256sum | cut -d' ' -f1)"
out="$(bash "$FANOUT" status --batches "$MX/b" --results "$MX/results" 2>&1)"
assert_eq "digest: regular, missing and directory entries match an independent computation" \
  "$(digest_of "$out" 01)" "$want"

# A FIFO at a listed path, or as the sidecar itself, is never opened. A stuck
# reader left by a regression is released by opening the FIFO read-write.
FF="$TEST_TMPDIR/fifo"
release() { local f; for f in "$@"; do [[ -p "$f" ]] && : <>"$f"; done; }
fifo_cases=(
  "fifo: status with a FIFO at a listed path exits 1 within the timeout"
  "fifo: that missing row says reason=paths"
  "fifo: an all-FIFO batch exits 1 within the timeout"
  "fifo: an all-FIFO batch says reason=paths"
  "fifo: a FIFO as the sidecar itself says reason=paths"
  "fifo: plan with a FIFO target exits 0 within the timeout"
  "fifo: plan counts the FIFO target as 0 words, with a warning"
  "fifo: plan still names the FIFO path in the sidecar"
  "fifo: cues.txt leaves the FIFO target out of scope_files"
  "fifo: plan with a FIFO targets file exits 2 within the timeout"
)
if command -v mkfifo >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1 &&
  mkdir -p "$FF/docs" "$FF/b1" "$FF/b2" "$FF/b3" "$FF/results" && mkfifo "$FF/docs/p.md" "$FF/docs/q.md" "$FF/b3/batch-01.paths"; then
  printf 'one\n' >"$FF/docs/x.md"
  printf 'x.md\np.md\n' >"$FF/b1/batch-01.txt"
  printf '%s\n' "$FF/docs/x.md" "$FF/docs/p.md" >"$FF/b1/batch-01.paths"
  timeout 10 bash "$FANOUT" status --batches "$FF/b1" --results "$FF/results" >"$FF/out1" 2>&1
  rc=$?
  release "$FF/docs/p.md"
  assert_exit "${fifo_cases[0]}" 1 "$rc"
  assert_contains "${fifo_cases[1]}" "$(cat "$FF/out1")" "batch=01 status=missing reason=paths digest="
  printf 'p.md\nq.md\n' >"$FF/b2/batch-01.txt"
  printf '%s\n' "$FF/docs/p.md" "$FF/docs/q.md" >"$FF/b2/batch-01.paths"
  timeout 10 bash "$FANOUT" status --batches "$FF/b2" --results "$FF/results" >"$FF/out2" 2>&1
  rc=$?
  release "$FF/docs/p.md" "$FF/docs/q.md"
  assert_exit "${fifo_cases[2]}" 1 "$rc"
  assert_contains "${fifo_cases[3]}" "$(cat "$FF/out2")" "batch=01 status=missing reason=paths digest="
  printf 'x.md\n' >"$FF/b3/batch-01.txt"
  timeout 10 bash "$FANOUT" status --batches "$FF/b3" --results "$FF/results" >"$FF/out3" 2>&1
  release "$FF/b3/batch-01.paths"
  assert_contains "${fifo_cases[4]}" "$(cat "$FF/out3")" "batch=01 status=missing reason=paths digest="
  printf '%s\t%s\n' x.md "$FF/docs/x.md" p.md "$FF/docs/p.md" >"$FF/targets.tsv"
  timeout 10 bash "$FANOUT" plan --out "$FF/planned" --order mtime "$FF/targets.tsv" >"$FF/out4" 2>&1
  rc=$?
  release "$FF/docs/p.md"
  assert_exit "${fifo_cases[5]}" 0 "$rc"
  assert_contains "${fifo_cases[6]}" "$(cat "$FF/out4")" "cannot read $FF/docs/p.md; counted as 0 words"
  assert_line_in "${fifo_cases[7]}" "$FF/planned/batch-01.paths" "$FF/docs/p.md"
  assert_line_in "${fifo_cases[8]}" "$FF/planned/cues.txt" "scope_files=1"
  mkfifo "$FF/targets-fifo.tsv"
  timeout 10 bash "$FANOUT" plan --out "$FF/planned-2" "$FF/targets-fifo.tsv" >/dev/null 2>&1
  rc=$?
  release "$FF/targets-fifo.tsv"
  assert_exit "${fifo_cases[9]}" 2 "$rc"
else
  for c in "${fifo_cases[@]}"; do skip "$c" "no mkfifo or timeout"; done
fi

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
assert_not_contains "merge: no cues.txt and no declines prints no consistency line" "$merged" "consistency"

# --- plan: cues.txt counts saturation cues over the whole scope ---------------------

K="$TEST_TMPDIR/cues"
mkdir -p "$K/docs"
printf 'This is load-bearing.\n' >"$K/docs/k01.md"
for n in 02 03 04 05 06 07 08 09 10; do printf 'load-bearing text\n' >"$K/docs/k$n.md"; done
printf 'A Load-Bearing wall, a load bearing beam, non-load-bearing trim.\r\n' >"$K/docs/k11.md"
cat >"$K/docs/k12.md" <<'EOF'
```
load-bearing in code
```
~~~
load-bearing
~~~
The seamless seam and seams.
  ```sh
seam
  ```
EOF
for n in 01 02 03 04 05 06 07 08 09 10 11 12; do printf 'k%s.md\t%s\n' "$n" "$K/docs/k$n.md"; done >"$K/targets.tsv"
out="$(bash "$FANOUT" plan --out "$K/batches" --order mtime "$K/targets.tsv" 2>/dev/null)"
assert_eq "cues: plan stdout is still one row per batch" "$out" "$(printf '%s\n' "$out" | grep '^batch=[0-9]* list=')"
assert_line_in "cues: scope_files counts the listed files" "$K/batches/cues.txt" "scope_files=12"
assert_line_in "cues: every match counts, fences skipped, saturated at 11 of 12 files" "$K/batches/cues.txt" \
  "cue=load-bearing occurrences=13 files=11 saturated=yes"
assert_line_in "cues: seamless is not seam, seams is, fenced seam is not" "$K/batches/cues.txt" \
  "cue=seam occurrences=2 files=1 saturated=no"
assert_line_in "cues: a per-batch line carries the batch's own counts" "$K/batches/cues.txt" \
  "batch=01 cue=load-bearing occurrences=13 files=11"

K2="$TEST_TMPDIR/cues-small"
mkdir -p "$K2"
printf 'load-bearing\n' >"$K2/a.md"
printf 'the load-bearing seam\n' >"$K2/b.md"
printf '%s\t%s\n' a.md "$K2/a.md" b.md "$K2/b.md" >"$K2/targets.tsv"
bash "$FANOUT" plan --out "$K2/batches" --order mtime "$K2/targets.tsv" >/dev/null 2>&1
assert_line_in "cues: two files in two are not saturated" "$K2/batches/cues.txt" \
  "cue=load-bearing occurrences=2 files=2 saturated=no"

# Counted only where the rubric reads: not frontmatter, blockquotes, code spans,
# double-quoted spans, or fences (any indent, closed only by a same-character
# run at least as long). One file per batch, newest first.
K3="$TEST_TMPDIR/cues-prose"
mkdir -p "$K3"
cat >"$K3/s1.md" <<'EOF'
---
title: load-bearing seam
---
Prose load-bearing here.
> quoted load-bearing
  > nested load-bearing
Code `load-bearing` and "load-bearing seam" and a seam.
EOF
printf 'intro\n---\nload-bearing\n---\n' >"$K3/s2.md"
cat >"$K3/s3.md" <<'EOF'
~~~~
```
load-bearing inside a long fence
```
~~~~
- item
    ```sh
    load-bearing in a list fence
    ```
````
load-bearing
```
still fenced load-bearing
````
After the fences load-bearing.
EOF
# Fences opened after list-item markers, nested, closed at an indent: the seam
# inside is code, the load-bearing after is prose.
cat >"$K3/s4.md" <<'EOF'
- ```sh
    seam inside a list fence
  ```
Prose after load-bearing.
1. - ~~~
     seam in a nested list fence
     ~~~
Then load-bearing again.
EOF
# A double-quoted span soft-wrapped onto the next line: its load-bearing is
# quoted, the seam after the closing quote is prose.
cat >"$K3/s5.md" <<'EOF'
He wrote "this passage wraps across
a load-bearing line" and then a seam here.
EOF
touch -t 202603010000 "$K3/s1.md"
touch -t 202602010000 "$K3/s2.md"
touch -t 202601010000 "$K3/s3.md"
touch -t 202512010000 "$K3/s4.md"
touch -t 202511010000 "$K3/s5.md"
printf '%s\t%s\n' s1.md "$K3/s1.md" s2.md "$K3/s2.md" s3.md "$K3/s3.md" s4.md "$K3/s4.md" s5.md "$K3/s5.md" >"$K3/targets.tsv"
bash "$FANOUT" plan --out "$K3/batches" --budget 1 --order mtime "$K3/targets.tsv" >/dev/null 2>&1
assert_line_in "cues: frontmatter, blockquotes, code and quoted spans are skipped" "$K3/batches/cues.txt" \
  "batch=01 cue=load-bearing occurrences=1 files=1"
assert_line_in "cues: a seam outside the quoted span still counts" "$K3/batches/cues.txt" \
  "batch=01 cue=seam occurrences=1 files=1"
assert_line_in "cues: a --- pair after line 1 is not frontmatter" "$K3/batches/cues.txt" \
  "batch=02 cue=load-bearing occurrences=1 files=1"
assert_line_in "cues: fences need a same-character closer at least as long, at any indent" "$K3/batches/cues.txt" \
  "batch=03 cue=load-bearing occurrences=1 files=1"
assert_line_in "cues: prose after a list-item fence counts" "$K3/batches/cues.txt" \
  "batch=04 cue=load-bearing occurrences=2 files=1"
assert_not_contains "cues: a cue inside a list-item fence does not" "$(cat "$K3/batches/cues.txt")" "batch=04 cue=seam"
assert_line_in "cues: a cue after a wrapped quote's close counts" "$K3/batches/cues.txt" \
  "batch=05 cue=seam occurrences=1 files=1"
assert_not_contains "cues: a cue inside a wrapped quote does not" "$(cat "$K3/batches/cues.txt")" "batch=05 cue=load-bearing"

# More non-prose, one file per batch: an inline triple-backtick span is not a
# fence opener; code spans close on a run of the same length; a first-line ---
# with no closer is not frontmatter; `...` closes frontmatter; a BOM before the
# frontmatter; HTML comments; link URLs; indented code; curly double quotes.
K4="$TEST_TMPDIR/cues-prose2"
mkdir -p "$K4"
BT='```'
# shellcheck disable=SC2016  # literal backticks, not a command substitution
k4=(
  "$(printf '%sx%s is code, the seam here is prose.\n\nAnother seam paragraph.\n' "$BT" "$BT")"
  "$(printf 'Use ``seam`` as a code span, ``a ` seam`` too. Then `x` seam.\n')"
  "$(printf -- '---\nseam one\n\nseam two\n')"
  "$(printf -- '---\ntitle: seam\n...\nbody seam\n')"
  "$(printf '\357\273\277---\nx: seam\n---\nbody seam\n')"
  "$(printf '<!-- seam note -->\ntext <!-- a\nseam\n--> after seam\n')"
  "$(printf 'See [the seam doc](https://example.com/seam) now.\n')"
  "$(printf 'para\n\n    seam in indented code\n\nprose seam\n- item\n\n    seam in a list paragraph\n')"
  "$(printf 'The word \342\200\234seam\342\200\235 is a mention; this seam is a use.\n')"
  "$(printf 'write <!-- to open\n\nseam after\n')"
)
for i in "${!k4[@]}"; do
  printf '%s\n' "${k4[$i]}" >"$K4/t$i.md"
  touch -t "2026010100$(printf '%02d' $((59 - i)))" "$K4/t$i.md"
  printf 't%s.md\t%s\n' "$i" "$K4/t$i.md"
done >"$K4/targets.tsv"
bash "$FANOUT" plan --out "$K4/batches" --budget 1 --order mtime "$K4/targets.tsv" >/dev/null 2>&1
k4want=(
  "an inline triple-backtick span opens no fence:2"
  "a double-backtick span closes on a double run:1"
  "a first-line --- with no closer is not frontmatter:2"
  "a ... line closes frontmatter:1"
  "a BOM before the frontmatter is stripped:1"
  "HTML comments are skipped, over lines too:1"
  "a link counts its text, not its URL:1"
  "an indented code block is skipped, a list paragraph is not:2"
  "curly double quotes span like straight ones:1"
  "a mid-line comment never closed is literal text:1"
)
for i in "${!k4want[@]}"; do
  assert_line_in "cues: ${k4want[$i]%:*}" "$K4/batches/cues.txt" \
    "batch=$(printf '%02d' $((i + 1))) cue=seam occurrences=${k4want[$i]##*:} files=1"
done

# CommonMark edges, one file per batch: a quoted <!-- opens no comment, an
# inline comment needs its -->, a line-start one runs to the end of the file,
# <!--> is a whole comment, a link destination holds no space, reference
# definitions and autolinks are not prose, and a heading ends its paragraph.
K5="$TEST_TMPDIR/cues-prose3"
mkdir -p "$K5"
k5=(
  "$(printf 'The "<!--" token and seam here.\n\nseam two\n')"
  "$(printf 'Type "<!--" to open a comment; the seam is here.\nA second seam line.\n\nLast seam.\n')"
  "$(printf 'text seam <!-- open seam\nmore seam\n\nafter seam\n')"
  "$(printf 'prose seam\n\n<!-- note seam\nmore seam\n\nafter seam\n')"
  "$(printf 'x <!--> seam -->\n')"
  "$(printf 'See [sic](the seam) here.\n')"
  "$(printf 'See [a](https://x/F_(seam) "seam title") and [b](<x y/seam>) seam.\n')"
  "$(printf 'See [seam text][ref] here.\n\n[ref]: https://x/seam "seam"\n')"
  "$(printf '[term]: this is a seam\n')"
  "$(printf 'Go to <https://x/seam> or <mailto:seam@x.y> now.\n')"
  "$(printf '# Title\n    seam code\n')"
  "$(printf '[ref]: https://x/u\n    seam\n')"
)
for i in "${!k5[@]}"; do
  printf '%s\n' "${k5[$i]}" >"$K5/t$i.md"
  touch -t "2026010100$(printf '%02d' $((59 - i)))" "$K5/t$i.md"
  printf 't%s.md\t%s\n' "$i" "$K5/t$i.md"
done >"$K5/targets.tsv"
bash "$FANOUT" plan --out "$K5/batches" --budget 1 --order mtime "$K5/targets.tsv" >/dev/null 2>&1
k5want=(
  "a quoted <!-- opens no comment:2"
  "a quoted <!-- leaves the rest of its paragraph prose:3"
  "an inline <!-- with no --> is literal text:4"
  "a line-start <!-- never closed runs to the end of the file:1"
  "<!--> is a whole comment:1"
  "a destination holding a space makes no link:1"
  "a destination with balanced parens, a title, or <brackets> is dropped:1"
  "a link reference definition is not prose:1"
  "a [term]: line with no destination is prose:1"
  "autolinks are not prose:0"
  "an indented line after a heading is code:0"
  "an indented line after a reference definition continues its paragraph:1"
)
for i in "${!k5want[@]}"; do
  line="batch=$(printf '%02d' $((i + 1))) cue=seam"
  if [[ "${k5want[$i]##*:}" == 0 ]]; then
    assert_not_contains "cues: ${k5want[$i]%:*}" "$(cat "$K5/batches/cues.txt")" "$line"
  else
    assert_line_in "cues: ${k5want[$i]%:*}" "$K5/batches/cues.txt" "$line occurrences=${k5want[$i]##*:} files=1"
  fi
done

: >"$K2/empty.tsv"
bash "$FANOUT" plan --out "$K2/empty" "$K2/empty.tsv" >/dev/null 2>&1
assert_eq "cues: an empty targets file writes no cues.txt" \
  "$([[ -e "$K2/empty/cues.txt" ]] && echo present || echo absent)" "absent"

# --- merge: cross-batch consistency over cues.txt ------------------------------------

# Replay: twelve files in three batches of four; load-bearing sits in ten of
# them (saturated), seam in one (not). Batch 01 reports load-bearing, batch 02
# declines it and seam as saturated, batch 03 holds load-bearing and says nothing.
X="$TEST_TMPDIR/replay"
mkdir -p "$X/docs" "$X/results" "$X/clean" "$X/old"
for n in 01 02 03 04 05 06 07 08 09 10 11 12; do
  case "$n" in
  05) printf 'a seam b c\n' ;;
  12) printf 'a b c d\n' ;;
  *) printf 'a load-bearing b c\n' ;;
  esac >"$X/docs/r$n.md"
  touch -t 202601010000 "$X/docs/r$n.md"
  printf 'r%s.md\t%s\n' "$n" "$X/docs/r$n.md"
done >"$X/targets.tsv"
plan="$(bash "$FANOUT" plan --out "$X/batches" --budget 16 --order mtime "$X/targets.tsv" 2>/dev/null)"
assert_eq "replay: plan packs three batches" "$(printf '%s\n' "$plan" | grep -c '^batch=')" "3"
assert_line_in "replay: load-bearing is saturated" "$X/batches/cues.txt" "cue=load-bearing occurrences=10 files=10 saturated=yes"
assert_line_in "replay: batch 03 holds load-bearing" "$X/batches/cues.txt" "batch=03 cue=load-bearing occurrences=3 files=3"
res() { # res <dir> <nn> <files_with_findings> <body>
  printf 'batch: %s\nfiles_reviewed: 4\nfiles_with_findings: %s\n%s\n' "$(digest_of "$plan" "$2")" "$3" "$4" >"$1/rubric-batch-$2.md"
}
res "$X/results" 01 1 $'\n## r01.md\n\n- L1 rule-abstract-metaphor-jargon: "a load-bearing b" -- metaphor jargon'
res "$X/results" 02 0 $'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated\ndeclined: rule-abstract-metaphor-jargon seam reason=saturated'
res "$X/results" 03 0 ""
out="$(bash "$FANOUT" status --batches "$X/batches" --results "$X/results" 2>&1)"
rc=$?
assert_exit "replay: status exits 0 with declined lines" 0 "$rc"
assert_contains "replay: a result with declined lines is complete" "$out" "batch=02 status=complete"
bash "$FANOUT" merge --batches "$X/batches" --results "$X/results" --out "$X/merged.md" >/dev/null 2>&1
rc=$?
assert_exit "replay: merge exits 0" 0 "$rc"
assert_line_in "replay: a saturated cue reported is flagged" "$X/merged.md" \
  "consistency: rule-abstract-metaphor-jargon cue=load-bearing saturated=yes reported_in=01"
assert_line_in "replay: a saturated decline of an unsaturated cue is flagged" "$X/merged.md" \
  "consistency: rule-abstract-metaphor-jargon cue=seam saturated=no declined_in=02"
assert_line_in "replay: a silent batch holding the cue is flagged" "$X/merged.md" \
  "consistency: rule-abstract-metaphor-jargon cue=load-bearing unaccounted_in=03"
assert_line_in "replay: the flagged rule's total says so" "$X/merged.md" \
  "rule_total: rule-abstract-metaphor-jargon=1 consistency=flagged"
assert_line_in "replay: declines are totaled per rule, cue and reason" "$X/merged.md" \
  "declined_total: rule-abstract-metaphor-jargon load-bearing reason=saturated batches=02"
assert_eq "replay: declined lines are stripped from the bodies" "$(grep -c '^declined:' "$X/merged.md")" "0"
assert_eq "replay: exactly three consistency lines" "$(grep -c '^consistency:' "$X/merged.md")" "3"

# Clean: every batch holding load-bearing declines it as saturated, and seam
# is reported. A cue named only outside the quote does not count as reported.
res "$X/clean" 01 0 'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated'
res "$X/clean" 02 1 $'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated\n\n## r05.md\n\n- L1 rule-abstract-metaphor-jargon: "a seam b" -- load-bearing style jargon'
res "$X/clean" 03 0 'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated'
bash "$FANOUT" merge --batches "$X/batches" --results "$X/clean" --out "$X/clean.md" >/dev/null 2>&1
assert_eq "clean: no consistency line" "$(grep -c 'consistency' "$X/clean.md")" "0"
assert_line_in "clean: the rule total is unflagged" "$X/clean.md" "rule_total: rule-abstract-metaphor-jargon=1"
assert_line_in "clean: declines from three batches total on one line" "$X/clean.md" \
  "declined_total: rule-abstract-metaphor-jargon load-bearing reason=saturated batches=01,02,03"

# A batch directory planned before cues.txt existed gets no consistency checks.
cp "$X"/batches/batch-* "$X/old/"
bash "$FANOUT" merge --batches "$X/old" --results "$X/results" --out "$X/old.md" >/dev/null 2>&1
rc=$?
assert_exit "no cues.txt: merge exits 0" 0 "$rc"
assert_eq "no cues.txt: no consistency line" "$(grep -c 'consistency' "$X/old.md")" "0"

# Decline reasons and quote parsing: boundary and cap account for a cue; a
# saturated decline of a cue cues.txt does not list is flagged; a declined:
# line with another reason stays in the body; an inner quote does not cut the
# quoted span short.
mkdir -p "$X/reasons"
res "$X/reasons" 01 0 'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated'
res "$X/reasons" 02 1 $'declined: rule-abstract-metaphor-jargon seam reason=boundary\ndeclined: rule-abstract-metaphor-jargon keystone reason=saturated\ndeclined: rule-abstract-metaphor-jargon seam reason=whatever\n\n## r05.md\n\n- L1 rule-abstract-metaphor-jargon: "a "b" load-bearing c" -- jargon'
res "$X/reasons" 03 0 'declined: rule-abstract-metaphor-jargon load-bearing reason=cap'
bash "$FANOUT" merge --batches "$X/batches" --results "$X/reasons" --out "$X/reasons.md" >/dev/null 2>&1
merged="$(cat "$X/reasons.md")"
assert_line_in "reasons: a cue after an inner quote is still in the quoted span" "$X/reasons.md" \
  "consistency: rule-abstract-metaphor-jargon cue=load-bearing saturated=yes reported_in=02"
assert_line_in "reasons: a saturated decline of a cue cues.txt does not list is flagged" "$X/reasons.md" \
  "consistency: rule-abstract-metaphor-jargon cue=keystone saturated=no declined_in=02"
assert_not_contains "reasons: a cap decline accounts for the cue" "$merged" "unaccounted_in=03"
assert_not_contains "reasons: a boundary decline accounts for the cue" "$merged" "cue=seam unaccounted_in"
assert_line_in "reasons: cap declines are totaled" "$X/reasons.md" \
  "declined_total: rule-abstract-metaphor-jargon load-bearing reason=cap batches=03"
assert_line_in "reasons: a declined: line with another reason stays in the body" "$X/reasons.md" \
  "declined: rule-abstract-metaphor-jargon seam reason=whatever"
assert_not_contains "reasons: and is not totaled" "$merged" "reason=whatever batches"

# A finding's quote may wrap onto indented continuation lines; a cue on one of
# them is reported, a cue after the closing quote is not.
mkdir -p "$X/wrap" "$X/wrap-out"
res "$X/wrap" 01 0 'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated'
res "$X/wrap" 02 1 $'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated\n\n## r05.md\n\n- L1 rule-abstract-metaphor-jargon: "a\n  seam\n  b" -- jargon'
res "$X/wrap" 03 0 'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated'
bash "$FANOUT" merge --batches "$X/batches" --results "$X/wrap" --out "$X/wrap.md" >/dev/null 2>&1
assert_eq "wrap: a cue on a quote's continuation line is reported" "$(grep -c '^consistency:' "$X/wrap.md")" "0"
res "$X/wrap-out" 01 0 'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated'
res "$X/wrap-out" 02 1 $'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated\n\n## r05.md\n\n- L1 rule-abstract-metaphor-jargon: "a\n  b" -- seam jargon'
res "$X/wrap-out" 03 0 'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated'
bash "$FANOUT" merge --batches "$X/batches" --results "$X/wrap-out" --out "$X/wrap-out.md" >/dev/null 2>&1
assert_line_in "wrap: a cue after the wrapped quote's close is not" "$X/wrap-out.md" \
  "consistency: rule-abstract-metaphor-jargon cue=seam unaccounted_in=02"

# A declined cue keys to the cue name whatever its case or plural.
mkdir -p "$X/norm"
res "$X/norm" 01 0 'declined: rule-abstract-metaphor-jargon Load-Bearing reason=saturated'
res "$X/norm" 02 0 $'declined: rule-abstract-metaphor-jargon load-bearing reason=saturated\ndeclined: rule-abstract-metaphor-jargon Seams reason=boundary\ndeclined: rule-abstract-metaphor-jargon load bearing reason=cap'
res "$X/norm" 03 0 'declined: rule-abstract-metaphor-jargon LOAD-BEARING reason=saturated'
bash "$FANOUT" merge --batches "$X/batches" --results "$X/norm" --out "$X/norm.md" >/dev/null 2>&1
assert_eq "norm: case and plural variants account for the cue" "$(grep -c '^consistency:' "$X/norm.md")" "0"
assert_line_in "norm: variants total under the cue name" "$X/norm.md" \
  "declined_total: rule-abstract-metaphor-jargon load-bearing reason=saturated batches=01,02,03"
assert_line_in "norm: a plural keys to its cue" "$X/norm.md" \
  "declined_total: rule-abstract-metaphor-jargon seam reason=boundary batches=02"
assert_line_in "norm: load bearing with a space keys to load-bearing" "$X/norm.md" \
  "declined_total: rule-abstract-metaphor-jargon load-bearing reason=cap batches=02"
assert_eq "norm: and is stripped from the body" "$(grep -c '^declined:' "$X/norm.md")" "0"

# cues.txt binds to the contents plan counted: after a listed file changes, and
# the stale batch is rerun to complete, merge says cues.txt is stale and skips
# the cue checks. A cues.txt without scope_digest is stale the same way.
SD="$TEST_TMPDIR/stale-cues"
mkdir -p "$SD/docs" "$SD/results" "$SD/old"
printf 'a load-bearing b\n' >"$SD/docs/a.md"
printf 'c d\n' >"$SD/docs/b.md"
printf '%s\t%s\n' a.md "$SD/docs/a.md" b.md "$SD/docs/b.md" >"$SD/targets.tsv"
plan="$(bash "$FANOUT" plan --out "$SD/batches" --order mtime "$SD/targets.tsv" 2>/dev/null)"
sres() { printf 'batch: %s\nfiles_reviewed: 2\nfiles_with_findings: 1\n\n## b.md\n\n- L1 rule-abstract-metaphor-jargon: "c d" -- x\n' "$1" >"$SD/results/rubric-batch-01.md"; }
sres "$(digest_of "$plan" 01)"
bash "$FANOUT" merge --batches "$SD/batches" --results "$SD/results" --out "$SD/fresh.md" >/dev/null 2>&1
assert_not_contains "stale cues: an untouched plan prints no stale line" "$(cat "$SD/fresh.md")" "cues.txt stale"
assert_line_in "stale cues: and still runs the cue checks" "$SD/fresh.md" \
  "consistency: rule-abstract-metaphor-jargon cue=load-bearing unaccounted_in=01"
cp "$SD"/batches/batch-* "$SD/old/"
grep -v '^scope_digest=' "$SD/batches/cues.txt" >"$SD/old/cues.txt"
bash "$FANOUT" merge --batches "$SD/old" --results "$SD/results" --out "$SD/old.md" >/dev/null 2>&1
assert_line_in "stale cues: a cues.txt with no scope_digest is stale" "$SD/old.md" "consistency: cues.txt stale reason=digest"
printf 'more\n' >>"$SD/docs/b.md"
out="$(bash "$FANOUT" status --batches "$SD/batches" --results "$SD/results" 2>&1)"
sres "$(digest_of "$out" 01)"
bash "$FANOUT" merge --batches "$SD/batches" --results "$SD/results" --out "$SD/stale.md" >/dev/null 2>&1
rc=$?
assert_exit "stale cues: merge of the rerun batch exits 0" 0 "$rc"
assert_line_in "stale cues: an edited listed file makes cues.txt stale" "$SD/stale.md" "consistency: cues.txt stale reason=digest"
assert_eq "stale cues: and no cue check runs" "$(grep -c '^consistency:' "$SD/stale.md")" "1"
assert_line_in "stale cues: nor flags the rule total" "$SD/stale.md" "rule_total: rule-abstract-metaphor-jargon=1"

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
