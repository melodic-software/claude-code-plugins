#!/usr/bin/env bash
# Tests for revert-cases.sh on a throwaway repository: list finds a pair by each revert form and
# skips a revert that removes no line its original added or no longer reverses cleanly; build
# writes a case whose scaffold rebuilds the change and whose grader matches the reverted lines;
# report counts caught and missed revert- cases and marks a small total as indicative.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$'\t'
fails=0
expect() {
  if [[ "$1" == 0 ]]; then
    echo "PASS: $2"
  else
    echo "FAIL: $2" >&2
    fails=1
  fi
}
has() {
  grep -qF -- "$1" <<<"$2"
  echo $?
}
same() {
  if [[ "$1" == "$2" ]]; then echo 0; else echo 1; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
mkdir -p "$WORK/evals" "$WORK/ws"
cp "$HERE/revert-cases.sh" "$WORK/evals/"
CASES="$WORK/evals/revert-cases.sh"

git init -q -b main "$REPO"
g() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
commit() { # <file> <content> <subject> [<git commit args>...]: prints the new commit
  printf "%b" "$2" >"$REPO/$1"
  g add -A
  g commit -q -m "$3" "${@:4}"
  g rev-parse HEAD
}

commit app.sh 'a\nb\nc\n' "chore: seed (#1)" >/dev/null
# shellcheck disable=SC2016 # the fixture file holds a literal $x
B="$(commit app.sh 'a\nx=1\necho "$x"\nb\nc\n' "feat: add x (#2)")"
commit other.txt 'note\n' "docs: other (#3)" >/dev/null
D="$(commit app.sh 'a\nb\nc\n' "revert: feat: add x (#4)" -m "This reverts commit $B.")"
F="$(commit other.txt 'note\ny=2\n' "fix: tweak y (#5)")"
G="$(commit other.txt 'note\n' "revert(docs): fix: tweak y")"
commit app.sh 'a\nb\n' "refactor: drop c (#7)" >/dev/null
J="$(commit app.sh 'a\nb\nc\n' "revert: refactor: drop c (#8)")"
commit app.sh 'a\nb\nc\nz=3\nw=1\n' "feat: add z (#9)" >/dev/null
commit app.sh 'a\nb\nc\nz=3\nw=2\n' "chore: bump w (#10)" >/dev/null
M="$(commit app.sh 'a\nb\nc\n' "revert: feat: add z (#11)")"
P="$(commit named.txt 'one\ntwo\n' "feat: add named (#12)")"
Q="$(commit named.txt 'one\n' "revert(docs): drop the second line (#13)" -m "Undoes #12 and mentions #999, which is not in this history.")"
R="$(commit named.txt 'three\n' "revert: rewrite named, naming nothing (#14)")"
V="$(commit named.txt 'four\n' "revert: rewrite named again (#15)" -m "Builds on #14, which was itself a revert.")"

out="$(cd "$REPO" && bash "$CASES" list 2>"$WORK/err")"
expect "$?" "list exits 0"
err="$(cat "$WORK/err")"
expect "$(same "$out" "#12${T}${P}${T}#13${T}${Q}"$'\n'"#5${T}${F}${T}-${T}${G}"$'\n'"#2${T}${B}${T}#4${T}${D}"$'\n'"pairs${T}3")" \
  "list prints the pull-request-number, subject-form and body-form pairs, newest first, and the count"
expect "$(has "skip${T}${R}${T}its original commit is not in this history" "$err")" \
  "list skips a revert that names no pull request and no matching subject"
expect "$(has "skip${T}${V}${T}its original commit is not in this history" "$err")" \
  "list does not pair a revert with an earlier revert it names"
expect "$(has "skip${T}${J}${T}removes no line #7 added" "$err")" "list skips a revert that only restores deleted lines"
expect "$(has "skip${T}${M}${T}#9 does not reverse cleanly" "$err")" "list skips a pair that no longer reverses cleanly"

case_out="$(cd "$REPO" && bash "$CASES" build "$B" "$D" add-x)"
expect "$?" "build exits 0"
case_dir="$WORK/evals/revert-2-add-x"
expect "$(same "$case_out" "$case_dir")" "build prints the case directory"
yaml="$(cat "$case_dir/case.yaml")"
expect "$(has "# revert: #4 $D" "$yaml")" "case.yaml records the revert"
expect "$(has "# pr: melodic-software/claude-code-plugins#2 (merged as $B)" "$yaml")" "case.yaml records the original"
expect "$(has "app.sh:2-3" "$yaml")" "case.yaml records the reverted lines"
expect "$(has "confirmed-by: pending" "$yaml")" "case.yaml leaves the confirmation pending"
expect "$(has "PR NUMBER: 2" "$(cat "$case_dir/prompt.md")")" "prompt names the original pull request"

(cd "$REPO" && bash "$CASES" build "$B" "$D" add-x) 2>/dev/null
code=$?
expect "$((code != 2))" "building an existing case exits 2"

mkdir -p "$WORK/unconfirmed"
(cd "$WORK/unconfirmed" && bash "$case_dir/scaffold.sh") 2>/dev/null
code=$?
expect "$((code != 2))" "scaffold refuses an unconfirmed case"
sed 's/^# confirmed-by: pending.*/# confirmed-by: verifier-agent/' "$case_dir/case.yaml" >"$WORK/case.yaml"
mv "$WORK/case.yaml" "$case_dir/case.yaml"

(cd "$WORK/ws" && bash "$case_dir/scaffold.sh")
expect "$?" "scaffold exits 0 once the case is confirmed"
expect "$(has "+x=1" "$(cat "$WORK/ws/.claude-lane/pr.diff")")" "scaffold writes the pull request's diff"
expect "$(has "feat: add x" "$(git -C "$WORK/ws" log -1 --format=%s)")" "scaffold commits the change under its subject"
expect "$(has "## Pull request #2: feat: add x" "$(cat "$WORK/ws/.claude-lane/pr-context.md")")" "scaffold writes the context"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node is not installed; grader and report not tested"
else
  pattern="$(sed -n "s/^pattern: '\(.*\)'$/\1/p" "$case_dir/graders/caught.md")"
  grade() { node -e 'process.exit(new RegExp(process.argv[1], "i").test(process.argv[2]) ? 0 : 1)' "$pattern" "$1"; }
  grade "| 1 | Blocking | app.sh:3 - echo prints an unset variable |"
  expect "$?" "grader passes a finding on a reverted line"
  grade "app.sh:4 - fine"
  code=$?
  expect "$((code != 1))" "grader fails a finding on another line"
  grade "myapp.sh:3 - unset variable"
  code=$?
  expect "$((code != 1))" "grader fails a finding on another file with the same suffix"

  cat >"$WORK/result.json" <<'JSON'
{"partial": false, "cases": [
  {"name": "revert-2-add-x", "arms": {"with": [{"passed": true, "error": null}]}},
  {"name": "revert-5-tweak-y", "arms": {"with": [{"passed": false, "error": null}]}},
  {"name": "revert-9-add-z", "arms": {"with": [{"passed": true, "error": "timeout"}]}},
  {"name": "recall-other", "arms": {"with": [{"passed": true, "error": null}]}}
]}
JSON
  out="$(bash "$CASES" report "$WORK/result.json")"
  expect "$?" "report exits 0"
  expect "$(has "caught${T}revert-2-add-x${T}1/1 runs" "$out")" "report marks a passing case caught"
  expect "$(has "missed${T}revert-5-tweak-y${T}0/1 runs" "$out")" "report marks a failing case missed"
  expect "$(has "not-comparable${T}revert-9-add-z" "$out")" "report sets aside a run with an error"
  expect "$(($(has "recall-other" "$out") == 0))" "report ignores other cases"
  expect "$(has "total${T}caught 1 of 2, 1 not comparable${T}indicative only: fewer than 5 cases" "$out")" \
    "report totals the comparable cases and marks a small set indicative"

  printf '{"partial": true, "partialReason": "cost_ceiling", "cases": []}\n' >"$WORK/partial.json"
  bash "$CASES" report "$WORK/partial.json" >/dev/null
  code=$?
  expect "$((code != 1))" "report on a partial run exits 1"
fi

bash "$CASES" frobnicate 2>/dev/null
code=$?
expect "$((code != 2))" "an unknown command exits 2"

if [[ $fails -eq 0 ]]; then
  echo "revert-cases.sh tests passed."
else
  echo "revert-cases.sh tests failed." >&2
fi
exit "$fails"
