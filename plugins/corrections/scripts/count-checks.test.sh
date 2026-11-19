#!/usr/bin/env bash
# Tests for count-checks.mjs over fixture repositories: the squash shape, a list-item line, trailing
# prose, a malformed and a placeholder line, a guidance rung, the semgrep-rule alias, the two 3.1.0
# rung ids, promotion by the advisory record's landing pull request, a repeated promoting line, a
# promoted advisory record later reverted, the task-list and code-span forms, prose mentions that
# are not records, first-parent history, reverts by hash and by pull request scoped to origin's
# repository, --since and --bucket, an empty history, usage that stops before history is read, and
# no file written.
# test-scope: plugins/corrections/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNT="$SCRIPT_DIR/count-checks.mjs"

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"

for tool in git node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "1..0 # SKIP $tool not available"
    exit 0
  fi
done

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$TEST_TMPDIR"
N=0

# new_repo: sets R to a new git repository on branch main.
new_repo() {
  N=$((N + 1))
  R="$TEST_TMPDIR/repo$N"
  mkdir -p "$R"
  git -C "$R" init -q -b main
  git -C "$R" config user.name tester
  git -C "$R" config user.email tester@example.invalid
  git -C "$R" config commit.gpgsign false
}
# commit <day> <message>: an empty commit dated at noon UTC on <day>; prints nothing.
commit() {
  GIT_AUTHOR_DATE="$1T12:00:00Z" GIT_COMMITTER_DATE="$1T12:00:00Z" \
    git -C "$R" commit -q --allow-empty --cleanup=verbatim -F - <<<"$2"
}
head_sha() { git -C "$R" rev-parse HEAD; }
# run <dir> <args...>: the counter from inside <dir>; stdout to $OUT, stderr to $ERR.
run() {
  local dir="$1"
  shift
  (cd "$dir" && node "$COUNT" "$@") >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err"
  RC=$?
  OUT="$(cat "$TEST_TMPDIR/out")"
  ERR="$(cat "$TEST_TMPDIR/err")"
}
has_line() { grep -qxF -- "$1" <<<"$OUT"; }

# 1. A history with every record shape.
new_repo
commit 2026-01-02 "chore: start"
commit 2026-01-05 "feat: layer test (#101)

## Summary

Adds the test.

Codifies: #50 rung=architecture-test blocking

Co-authored-by: Someone <someone@example.invalid>"
commit 2026-01-06 "feat: list item (#102)

- Codifies: #51 rung=custom-analyzer blocking"
commit 2026-01-07 "feat: trailing prose (#103)

Codifies: #52 rung=custom-analyzer blocking see the issue"
commit 2026-01-08 "feat: malformed (#104)

Codifies: 52 rung=custom-analyzer blocking
Codifies: <#issue-or-PR | session> rung=<rung id> <blocking|advisory>"
commit 2026-01-09 "docs: guidance (#105)

Codifies: #54 rung=instruction blocking"
commit 2026-01-10 "feat: advisory analyzer (#106)

Codifies: #60 rung=custom-analyzer advisory"
commit 2026-01-20 "feat: old rung id (#107)

Codifies: #53 rung=semgrep-rule advisory"
commit 2026-02-03 "test: behavior (#108)

Codifies: session rung=behavior-test blocking"
commit 2026-02-04 "build: strict mode (#109)

Codifies: #80 rung=compiler-setting advisory"
commit 2026-02-10 "feat: analyzer blocks (#110)

Codifies: #106 rung=custom-analyzer blocking"
commit 2026-02-12 "feat: guard (#120)

Codifies: #70 rung=action-guard blocking"
commit 2026-02-13 "feat: another guard (#122)

Codifies: #71 rung=action-guard blocking"
REVERT_ME="$(head_sha)"
commit 2026-02-14 'Revert "feat: guard (#120)" (#121)

Reverts example/repo#120'
commit 2026-02-15 "Revert \"feat: another guard (#122)\"

This reverts commit $REVERT_ME."

run "$R" --since 2026-01-01 --until 2026-02-28
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "full history: exits 0" test "$RC" -eq 0
HEADER='| period | blocking | advisory | cumulative blocking | cumulative advisory | compiler-setting | custom-analyzer | syntax-pattern-rule | architecture-test | behavior-test |'
DETAIL="out: $OUT"
check "full history: a column per rung that occurs, in ladder order, the new ids included" has_line "$HEADER"
DETAIL="out: $OUT"
check "full history: January counts the squash-shape record and two advisory ones" has_line '| 2026-01 | 1 | 2 | 1 | 2 | 0 | 1 | 1 | 1 | 0 |'
DETAIL="out: $OUT"
check "full history: February counts the promotion once, in the blocking column" has_line '| 2026-02 | 2 | 0 | 3 | 2 | 1 | 0 | 0 | 0 | 1 |'
DETAIL="out: $OUT"
check "full history: the window row totals the window" has_line '| window | 3 | 2 | 3 | 2 | 1 | 1 | 1 | 1 | 1 |'
DETAIL="out: $OUT"
check "full history: no ratio is printed" test "$(grep -ciE 'ratio|%' <<<"$OUT")" -eq 0
DETAIL="out: $OUT"
check "full history: the promotion is listed" grep -qE '^  [0-9a-f]{12} 2026-02-10 #106 rung=custom-analyzer, advisory in [0-9a-f]{12}$' <<<"$OUT"
DETAIL="out: $OUT"
check "full history: with no origin remote, a qualified Reverts line is matched by number and the output says so" \
  has_line 'no owner/repo read from an origin remote URL: 1 "Reverts <owner>/<repo>#<n>" line(s) matched by number alone'
DETAIL="out: $OUT"
check "full history: the alias is listed" grep -qE '^  [0-9a-f]{12} 2026-01-20 rung=semgrep-rule read as rung=syntax-pattern-rule$' <<<"$OUT"
DETAIL="out: $OUT"
check "full history: both reverted records are listed, not counted" has_line "reverted, not counted: 2"
DETAIL="out: $OUT"
check "full history: a revert by pull request number is listed" grep -qF '"Codifies: #70 rung=action-guard blocking" reverted by' <<<"$OUT"
DETAIL="out: $OUT"
check "full history: a revert by commit hash is listed" grep -qF '"Codifies: #71 rung=action-guard blocking" reverted by' <<<"$OUT"
DETAIL="out: $OUT"
check "full history: five lines are not counted" has_line "not counted: 5"
DETAIL="out: $OUT"
check "not counted: a list-item line, with its commit" grep -qE '^  [0-9a-f]{12} 2026-01-06 a list item, not a line of its own at column 0: "- Codifies: #51' <<<"$OUT"
DETAIL="out: $OUT"
check "not counted: a line with trailing prose" grep -qF 'other text on the line: "Codifies: #52 rung=custom-analyzer blocking see the issue"' <<<"$OUT"
DETAIL="out: $OUT"
check "not counted: a malformed line" grep -qF 'malformed: does not match the record grammar: "Codifies: 52 rung=custom-analyzer blocking"' <<<"$OUT"
DETAIL="out: $OUT"
check "not counted: the placeholder line" grep -qF 'malformed: does not match the record grammar: "Codifies: <#issue-or-PR | session>' <<<"$OUT"
DETAIL="out: $OUT"
check "not counted: a guidance rung" grep -qF 'rung=instruction is a guidance or human-review rung, which is not counted' <<<"$OUT"
DETAIL="git status: $(git -C "$R" status --porcelain)"
check "full history: writes no file" test -z "$(git -C "$R" status --porcelain --untracked-files=all)"

# With no --since, the window opens at the first record line, a not-counted one included.
run "$R" --until 2026-02-28
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "no --since: the window opens at the first record line" has_line "window: 2026-01-05 to 2026-02-28, bucket: month"

# 2. --since: the cumulative value counts from the first record in history.
run "$R" --since 2026-02-01 --until 2026-02-28
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "--since: the rung columns are those that occur in the window" \
  has_line '| period | blocking | advisory | cumulative blocking | cumulative advisory | compiler-setting | behavior-test |'
DETAIL="out: $OUT"
check "--since: the period row carries the cumulative from before the window" has_line '| 2026-02 | 2 | 0 | 3 | 2 | 1 | 1 |'
DETAIL="out: $OUT"
check "--since: the window row" has_line '| window | 2 | 0 | 3 | 2 | 1 | 1 |'
DETAIL="out: $OUT"
check "--since: a record before the window is not listed" test "$(grep -c '2026-01-06' <<<"$OUT")" -eq 0

# 3. --bucket week.
run "$R" --bucket week --since 2026-01-05 --until 2026-01-18
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "--bucket week: one row per ISO week, from its Monday" has_line '| week of 2026-01-05 | 1 | 1 | 1 | 1 | 1 | 1 |'
DETAIL="out: $OUT"
check "--bucket week: an empty week keeps the cumulative" has_line '| week of 2026-01-12 | 0 | 0 | 1 | 1 | 0 | 0 |'

# 3a. Promotion identity: a blocking record promotes the advisory record landed by the pull request
# it names as its source, whatever that advisory record's own source was.
new_repo
commit 2026-04-01 "feat: advisory from a session (#200)

Codifies: session rung=custom-analyzer advisory"
commit 2026-04-10 "feat: make it blocking (#201)

Codifies: #200 rung=custom-analyzer blocking"
commit 2026-04-15 "feat: first check for issue 7 (#202)

Codifies: #7 rung=architecture-test advisory"
commit 2026-04-20 "feat: second check for issue 7 (#203)

Codifies: #7 rung=architecture-test blocking"
run "$R" --since 2026-04-01 --until 2026-04-30
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "promotion: a session-sourced advisory check made blocking is counted once; two checks sharing #7 are two" \
  has_line '| 2026-04 | 2 | 1 | 2 | 1 | 1 | 2 |'
DETAIL="out: $OUT"
check "promotion: only the session-sourced check is promoted" has_line "promoted from advisory to blocking: 1"
DETAIL="out: $OUT"
check "promotion: the promoting line names the pull request that landed the advisory record" \
  grep -qE '^  [0-9a-f]{12} 2026-04-10 #200 rung=custom-analyzer, advisory in [0-9a-f]{12}$' <<<"$OUT"
DETAIL="out: $OUT"
check "promotion: with no advisory record reverted, no line is listed as origin-reverted" \
  has_line "blocking, its advisory origin reverted, counted as a new blocking check: 0"

# 3b. Every other line holding an attempted record is listed with its reason, the task-list form
# included; a mention of Codifies: with no record after it is not listed.
new_repo
# shellcheck disable=SC2016 # the backticks are literal Markdown code spans
commit 2026-05-01 'feat: issue form (#300)

- [ ] The PR body carries `Codifies: #9 rung=architecture-test blocking`.
`Codifies: #9 rung=architecture-test blocking`
Adds the record Codifies: #9 rung=architecture-test blocking to the body.
Adds a `Codifies:` line to the body.'
run "$R" --since 2026-05-01 --until 2026-05-31
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "placement: nothing is counted" has_line '| window | 0 | 0 | 0 | 0 |'
DETAIL="out: $OUT"
check "placement: the three record lines are listed as not counted, the bare mention is not" has_line "not counted: 3"
DETAIL="out: $OUT"
# shellcheck disable=SC2016 # literal code spans
check "placement: the task-list item form" \
  grep -qF 'a list item quoting it in a code span, not a line of its own at column 0: "- [ ] The PR body carries `Codifies: #9' <<<"$OUT"
DETAIL="out: $OUT"
# shellcheck disable=SC2016 # literal code spans
check "placement: a record inside a code span" \
  grep -qF 'a code span, not a line of its own at column 0: "`Codifies: #9 rung=architecture-test blocking`"' <<<"$OUT"
DETAIL="out: $OUT"
# shellcheck disable=SC2016 # literal code spans
check "placement: a record inside prose" \
  grep -qF 'a line of other text, not a line of its own at column 0: "Adds the record Codifies: #9' <<<"$OUT"
DETAIL="out: $OUT"
# shellcheck disable=SC2016 # literal code spans
check "placement: a bare mention inside prose is not listed" test "$(grep -c 'Adds a `Codifies:` line' <<<"$OUT")" -eq 0

# 3b-1. A squash message whose subject and prose mention Codifies: without a record adds nothing to
# not counted and does not open the window.
new_repo
commit 2026-08-01 "feat(corrections): count Codifies: records (#600)

> Adds a count of the checks merged changes record with a Codifies: line in the body.

- scripts/report.mjs: copies a Codifies: record from a task-list item naming the PR body."
commit 2026-09-03 "feat: first real check (#601)

Codifies: #16 rung=custom-analyzer blocking"
run "$R" --until 2026-10-31
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "mentions: with no --since the window opens at the first record, not the first mention" \
  has_line "window: 2026-09-03 to 2026-10-31, bucket: month"
DETAIL="out: $OUT"
check "mentions: the record is counted in September" has_line '| 2026-09 | 1 | 0 | 1 | 0 | 1 |'
DETAIL="out: $OUT"
check "mentions: nothing is listed as not counted" has_line "not counted: 0"
run "$R" --since 2026-08-01 --until 2026-10-31
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "mentions: inside the window, the mentions are still not listed" has_line "not counted: 0"

# 3b-1a. A malformed line at column 0, older than every record, opens the default window and is
# listed.
new_repo
commit 2026-03-01 "feat: analyzer (#11)

Codifies: issue-12 custom-analyzer blocking"
commit 2026-06-01 "feat: check (#12)

Codifies: #5 rung=custom-analyzer blocking"
run "$R" --until 2026-07-31
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "malformed at column 0: with no --since it opens the window" \
  has_line "window: 2026-03-01 to 2026-07-31, bucket: month"
DETAIL="out: $OUT"
check "malformed at column 0: it is listed" has_line "not counted: 1"
DETAIL="out: $OUT"
check "malformed at column 0: with its reason" \
  grep -qF 'malformed: does not match the record grammar: "Codifies: issue-12 custom-analyzer blocking"' <<<"$OUT"
DETAIL="out: $OUT"
check "malformed at column 0: the later record is counted in June" has_line '| 2026-06 | 1 | 0 | 1 | 0 | 1 |'

# 3b-1b. A record written with emphasis on the key is listed; a quoted grammar with placeholders is
# not; a harmless repeat of an advisory line carries no promotion hint.
new_repo
# shellcheck disable=SC2016 # the backticks are literal Markdown code spans
commit 2026-04-01 'docs: explain the record line (#16)

The record is `Codifies: <#n | session> rung=<id> <kind>`.
**Codifies:** #13 action-guard blocking'
commit 2026-04-02 "feat: boundary test (#14)

Codifies: #15 rung=architecture-test advisory

Co-authored-by: a <a@example.invalid>

Codifies: #15 rung=architecture-test advisory"
run "$R" --since 2026-04-01 --until 2026-04-30
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "forms: the emphasis form and the repeat are listed, the quoted grammar is not" has_line "not counted: 2"
DETAIL="out: $OUT"
check "forms: the emphasis form is listed" grep -qF '**Codifies:** #13 action-guard blocking' <<<"$OUT"
DETAIL="out: $OUT"
check "forms: the quoted grammar is not listed" test "$(grep -c 'session> rung=<id>' <<<"$OUT")" -eq 0
DETAIL="out: $OUT"
check "forms: the advisory record counts once" has_line '| window | 0 | 1 | 0 | 1 | 1 |'
DETAIL="out: $OUT"
check "forms: the repeat is listed as a repeat" \
  grep -qF 'repeats a line earlier in this commit message, which counts once: "Codifies: #15 rung=architecture-test advisory"' <<<"$OUT"
DETAIL="out: $OUT"
check "forms: an advisory repeat carries no promotion hint" test "$(grep -c 'two promotions' <<<"$OUT")" -eq 0

# 3b-2. Two same-rung advisory records landed by one pull request: one promoting line promotes one,
# its repeat in the same message is listed, and a second commit promotes the other.
new_repo
commit 2026-08-03 "feat: two analyzers (#700)

Codifies: #7 rung=custom-analyzer advisory
Codifies: #8 rung=custom-analyzer advisory"
commit 2026-08-10 "feat: both analyzers block (#701)

Codifies: #700 rung=custom-analyzer blocking
Codifies: #700 rung=custom-analyzer blocking"
run "$R" --since 2026-08-01 --until 2026-08-11
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "repeat: the repeated promoting line promotes one check" has_line '| window | 1 | 1 | 1 | 1 | 2 |'
DETAIL="out: $OUT"
check "repeat: one promotion" has_line "promoted from advisory to blocking: 1"
DETAIL="out: $OUT"
check "repeat: the repeated line is listed as not counted, with its reason" \
  grep -qE '^  [0-9a-f]{12} 2026-08-10 repeats a line earlier in this commit message, which counts once \(two promotions of the same source and rung need two commits\): "Codifies: #700 rung=custom-analyzer blocking"$' <<<"$OUT"
commit 2026-08-12 "feat: the other analyzer blocks (#702)

Codifies: #700 rung=custom-analyzer blocking"
run "$R" --since 2026-08-01 --until 2026-08-31
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "repeat: a promotion in its own commit promotes the second check" has_line '| window | 2 | 0 | 2 | 0 | 2 |'
DETAIL="out: $OUT"
check "repeat: two promotions" has_line "promoted from advisory to blocking: 2"

# 3b-3. An advisory record reverted after its promotion: the promoting line stands as a new blocking
# check and is listed with the reverted advisory record.
new_repo
commit 2026-09-01 "feat: analyzer (#800)

Codifies: #9 rung=custom-analyzer advisory"
ADVISORY="$(head_sha)"
commit 2026-09-05 "feat: analyzer blocks (#801)

Codifies: #800 rung=custom-analyzer blocking"
commit 2026-09-10 'Revert "feat: analyzer (#800)" (#802)

Reverts #800'
REVERTER="$(head_sha)"
run "$R" --since 2026-09-01 --until 2026-09-30
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "origin reverted: the promoting line counts as one new blocking check" has_line '| window | 1 | 0 | 1 | 0 | 1 |'
DETAIL="out: $OUT"
check "origin reverted: no promotion" has_line "promoted from advisory to blocking: 0"
DETAIL="out: $OUT"
check "origin reverted: the promoting line is listed with the reverted advisory record" \
  grep -qE "^  [0-9a-f]{12} 2026-09-05 #800 rung=custom-analyzer, advisory in ${ADVISORY:0:12} reverted by ${REVERTER:0:12}\$" <<<"$OUT"
DETAIL="out: $OUT"
check "origin reverted: one such line" has_line "blocking, its advisory origin reverted, counted as a new blocking check: 1"
DETAIL="out: $OUT"
check "origin reverted: the advisory record is listed as reverted" has_line "reverted, not counted: 1"

# 3c. First-parent history: a branch commit and its merge commit both carrying the line count once.
new_repo
commit 2026-06-01 "chore: start"
git -C "$R" switch -q -c topic
commit 2026-06-02 "feat: branch work

Codifies: #11 rung=behavior-test blocking"
git -C "$R" switch -q main
GIT_AUTHOR_DATE="2026-06-03T12:00:00Z" GIT_COMMITTER_DATE="2026-06-03T12:00:00Z" \
  git -C "$R" merge -q --no-ff topic -m "Merge pull request #400 from topic" -m "Codifies: #11 rung=behavior-test blocking"
run "$R" --since 2026-06-01 --until 2026-06-30
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "first parent: the merged line is counted once" has_line '| window | 1 | 0 | 1 | 0 | 1 |'

# 3d. Reverts owner/repo#n reverts only when owner/repo is origin's (compared without case).
new_repo
git -C "$R" remote add origin git@github.com:Example/Repo.git
commit 2026-07-01 "feat: guard (#500)

Codifies: #90 rung=action-guard blocking"
commit 2026-07-02 "feat: other guard (#501)

Codifies: #91 rung=action-guard blocking"
commit 2026-07-03 'Revert "a change elsewhere" (#502)

Reverts other/project#500'
commit 2026-07-04 'Revert "feat: other guard (#501)" (#503)

Reverts example/repo#501'
run "$R" --since 2026-07-01 --until 2026-07-31
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "reverts by repository: another repository's #500 leaves this one's record counted" has_line '| window | 1 | 0 | 1 | 0 | 1 |'
DETAIL="out: $OUT"
check "reverts by repository: this repository's #501 is reverted" \
  grep -qF '"Codifies: #91 rung=action-guard blocking" reverted by' <<<"$OUT"
DETAIL="out: $OUT"
check "reverts by repository: one record is reverted" has_line "reverted, not counted: 1"
DETAIL="out: $OUT"
check "reverts by repository: with origin read, no number-only note" test "$(grep -c 'no owner/repo read' <<<"$OUT")" -eq 0

# 3e. An origin URL with no owner/repo in it is treated like no origin: a qualified Reverts line is
# matched by number and the output says so.
new_repo
git -C "$R" remote add origin not-a-url
commit 2026-07-10 "feat: guard (#900)

Codifies: #92 rung=action-guard blocking"
commit 2026-07-11 'Revert "feat: guard (#900)" (#901)

Reverts example/repo#900'
run "$R" --since 2026-07-01 --until 2026-07-31
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "unreadable origin URL: the number-only note names the URL, not a missing remote" \
  has_line 'no owner/repo read from an origin remote URL: 1 "Reverts <owner>/<repo>#<n>" line(s) matched by number alone'
DETAIL="out: $OUT"
check "unreadable origin URL: the record is reverted by number" has_line "reverted, not counted: 1"

# 4. An empty history prints zeros.
new_repo
commit 2026-03-02 "chore: nothing codified"
run "$R" --since 2026-03-01 --until 2026-03-31
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "empty history: exits 0" test "$RC" -eq 0
DETAIL="out: $OUT"
check "empty history: the period row is zeros" has_line '| 2026-03 | 0 | 0 | 0 | 0 |'
DETAIL="out: $OUT"
check "empty history: the window row is zeros" has_line '| window | 0 | 0 | 0 | 0 |'
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "empty history, no window given: exits 0 with a zero window row" test "$RC" -eq 0 -a -n "$(grep -xF '| window | 0 | 0 | 0 | 0 |' <<<"$OUT")"

# 5. A bad value stops before history is read: outside a repository it still exits 2, not 1.
mkdir -p "$TEST_TMPDIR/not-a-repo"
for args in "--since 2026-02-30" "--since yesterday" "--until 2026-13-01" "--bucket day" \
  "--since 2026-02-02 --until 2026-02-01" "--since 2999-01-01" "--bogus" "extra" "--since"; do
  # shellcheck disable=SC2086 # each case is a word list
  run "$TEST_TMPDIR/not-a-repo" $args
  DETAIL="exit $RC; out: $OUT; stderr: $ERR"
  check "usage ($args): exits 2 and prints nothing to stdout" test "$RC" -eq 2 -a -z "$OUT"
done

# 6. Outside a repository there is no default branch.
run "$TEST_TMPDIR/not-a-repo"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "outside a repository: exits 1 and names the missing default branch" test "$RC" -eq 1 -a -n "$(grep 'no default branch' <<<"$ERR")"

printf '1..%d\n' "$CASE_NUM"
if [[ $FAILED -gt 0 ]]; then
  echo "# $FAILED of $CASE_NUM failed"
  exit 1
fi
