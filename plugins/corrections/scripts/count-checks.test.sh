#!/usr/bin/env bash
# Tests for count-checks.mjs over fixture repositories: the squash shape, a list-item line, trailing
# prose, a malformed and a placeholder line, a guidance rung, the semgrep-rule alias, the two 3.1.0
# rung ids, a promotion, reverts by hash and by pull request, --since and --bucket, an empty
# history, usage that stops before history is read, and no file written.
# test-scope: plugins/corrections/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNT="$SCRIPT_DIR/count-checks.mjs"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'ok %d - %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n' "$CASE_NUM" "$1"
  if [[ -n "${2:-}" ]]; then printf '  %s\n' "$2"; fi
}
# check <name> <command...>: passes when the command exits 0.
check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name" "${DETAIL:-}"; fi
  DETAIL=""
}

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

Codifies: #60 rung=custom-analyzer blocking"
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
check "full history: the promotion is listed" grep -qE '^  [0-9a-f]{12} 2026-02-10 #60 rung=custom-analyzer, advisory in [0-9a-f]{12}$' <<<"$OUT"
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
