#!/usr/bin/env bash
# Tests for the eval fixture forge (fixtures/gh-forge): install.sh in a throwaway repository, then the gh stand-in it
# installs. Expected values come from GitHub's mergeStateStatus enum (UNSTABLE: mergeable with a
# non-passing commit status) and gh's `pr checks` source (the --json path exits 0 whatever the
# checks say; the table exits 1 when one failed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../scripts/test-helpers.sh
source "$SCRIPT_DIR/../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

# make_forge <dir> [install.sh options...]: a repository with main and a head branch one commit
# ahead, given an offline forge serving PR 7 from them.
make_forge() {
  local repo="$TEST_TMPDIR/$1"
  shift
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.name eval
    git config user.email eval@example.invalid
    echo a >f
    git add f
    git commit -q -m seed
    git checkout -q -b feat/x
    echo b >f
    git commit -q -am change
    bash "$SCRIPT_DIR/fixtures/gh-forge/install.sh" 7 feat/x main "feat: x" "$@"
  ) >/dev/null 2>&1
  assert_exit "install.sh $*: exit 0" 0 "$?"
}

run_gh() {
  local repo="$1"
  shift
  (cd "$repo" && "$repo/.git/eval-forge/bin/gh" "$@")
}

FAILING="$TEST_TMPDIR/failing" GREEN="$TEST_TMPDIR/green"
make_forge failing --open --failing-check integration-tests
make_forge green --open

out=$(run_gh "$FAILING" pr view 7 --json mergeStateStatus --jq .mergeStateStatus)
assert_eq "failing check: the PR reads UNSTABLE, never CLEAN" "UNSTABLE" "$out"

out=$(run_gh "$GREEN" pr view 7 --json mergeStateStatus --jq .mergeStateStatus)
assert_eq "no checks, head up to date: the PR reads CLEAN" "CLEAN" "$out"

out=$(run_gh "$FAILING" pr checks 7 --json name,bucket --jq '.[] | "\(.name) \(.bucket)"')
rc=$?
assert_exit "pr checks --json: exit 0 with a failed check" 0 "$rc"
assert_eq "pr checks --json: the failed check is listed" "integration-tests fail" "$out"

run_gh "$FAILING" pr checks 7 >/dev/null
assert_exit "pr checks table: exit 1 with a failed check" 1 "$?"

helper=missing
[[ -x "$GREEN/.git/eval-forge/bin/git-remote-evalforge" ]] && helper=executable
assert_eq "install.sh: git-remote-evalforge lands executable beside the gh stand-in" executable "$helper"

# push-branch.sh through the helper: origin reads as github.com, the bytes land in the bare repository.
PUSH="$SCRIPT_DIR/../skills/pull-request/scripts/push-branch.sh"
FORGE_PATH="$GREEN/.git/eval-forge/bin:$PATH"
(
  cd "$GREEN" || exit 1
  echo c >f
  PATH="$FORGE_PATH" git commit -q -am more
  PATH="$FORGE_PATH" bash "$PUSH" --pr 7
) >/dev/null 2>&1
assert_exit "push-branch.sh --pr 7: exit 0 against the fixture origin" 0 "$?"
assert_eq "push-branch.sh: the bare origin's head ref equals local HEAD" \
  "$(git -C "$GREEN" rev-parse HEAD)" "$(git -C "$GREEN/.git/eval-forge/eval-fixture/app.git" rev-parse feat/x)"
(cd "$GREEN" && PATH="$FORGE_PATH" git fetch origin) >/dev/null 2>&1
assert_exit "git fetch origin succeeds through the helper" 0 "$?"

# The babysit cycle's commands. THREADED has an open PR with two unresolved review threads.
THREADED="$TEST_TMPDIR/threaded"
make_forge threaded --open --thread T_one --thread T_two
CALLS="$THREADED/.git/eval-forge/calls.jsonl"

refs_before=$(
  git -C "$THREADED" for-each-ref --format='%(refname) %(objectname)'
  git -C "$THREADED/.git/eval-forge/eval-fixture/app.git" for-each-ref --format='%(refname) %(objectname)'
)
out=$(run_gh "$THREADED" pr merge 7 --squash --delete-branch 2>&1)
assert_exit "pr merge: exit 0" 0 "$?"
assert_eq "pr merge: the call record holds the PR number and arguments" \
  '{"command":"pr merge","pr":7,"args":["7","--squash","--delete-branch"]}' "$(cat "$CALLS")"
refs_after=$(
  git -C "$THREADED" for-each-ref --format='%(refname) %(objectname)'
  git -C "$THREADED/.git/eval-forge/eval-fixture/app.git" for-each-ref --format='%(refname) %(objectname)'
)
assert_eq "pr merge: no ref changed, in the working repository or the fixture origin" "$refs_before" "$refs_after"
run_gh "$THREADED" pr merge 99 >/dev/null 2>&1
assert_exit "pr merge: another PR number is refused" 1 "$?"
assert_eq "pr merge: a refused call leaves no record" 1 "$(wc -l <"$CALLS" | tr -d ' ')"

# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
THREADS_QUERY='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved}}}}}'
out=$(run_gh "$THREADED" api graphql -f "query=$THREADS_QUERY" -F o=eval-fixture -F r=app -F n=7 \
  --jq '.data.repository.pullRequest.reviewThreads.nodes | map(.id + ":" + (.isResolved | tostring)) | join(",")' 2>&1)
assert_eq "api graphql: review threads come from the fixture state" "T_one:false,T_two:false" "$out"

# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
RESOLVE='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'
out=$(run_gh "$THREADED" api graphql -f "query=$RESOLVE" -f id=T_one 2>&1)
assert_eq "api graphql: resolve-thread answers isResolved true" "true" "$(jq -r '.data.resolveReviewThread.thread.isResolved' <<<"$out")"
assert_eq "api graphql: resolve-thread is recorded like a merge" \
  '{"command":"resolve thread","pr":7,"args":["T_one"]}' "$(tail -n 1 "$CALLS")"
out=$(run_gh "$THREADED" api graphql -f "query=$THREADS_QUERY" --jq '.data.repository.pullRequest.reviewThreads.nodes | map(.isResolved | tostring) | join(",")' 2>&1)
assert_eq "api graphql: the resolved thread reads resolved afterwards" "true,false" "$out"
run_gh "$THREADED" api graphql -f 'query=mutation{deleteRepository}' >/dev/null 2>&1
assert_exit "api graphql: any other query is refused" 1 "$?"

# --outdated-bot-thread serves a bot-authored thread GitHub marks outdated, in argument order.
BOTTHREAD="$TEST_TMPDIR/botthread"
make_forge botthread --open --thread T_human --outdated-bot-thread T_bot
out=$(run_gh "$BOTTHREAD" api graphql -f "query=$THREADS_QUERY" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes | map("\(.id):\(.isOutdated):\(.comments.nodes[0].author.__typename)") | join(",")' 2>&1)
assert_eq "api graphql: --outdated-bot-thread is outdated and bot-authored, --thread is neither" \
  "T_human:false:User,T_bot:true:Bot" "$out"

out=$(run_gh "$THREADED" api user --jq .login 2>&1)
assert_eq "api user: serves the fixture login" "eval-fixture" "$out"

out=$(run_gh "$THREADED" search prs --author eval-fixture --json number,title --jq '.[] | "\(.number) \(.title)"' 2>&1)
assert_eq "search prs: serves the fixture pull request" "7 feat: x" "$out"
assert_eq "search prs: the served call is recorded as a read" "read search prs" \
  "$(tail -n 1 "$CALLS" | jq -r '"\(.command) \(.args[0]) \(.args[1])"')"

out=$(run_gh "$THREADED" pr review 7 --approve --body ok 2>&1)
assert_exit "pr review: exit 0" 0 "$?"
assert_eq "pr review: the call is recorded" \
  '{"command":"pr review","pr":7,"args":["7","--approve","--body","ok"]}' "$(tail -n 1 "$CALLS")"

out=$(printf 'skipped\n' | run_gh "$THREADED" pr comment 7 --body-file - 2>&1)
assert_exit "pr comment: exit 0" 0 "$?"
assert_eq "pr comment: the call is recorded" \
  '{"command":"pr comment","pr":7,"args":["7","--body-file","-"]}' "$(tail -n 1 "$CALLS")"

# The eval sandbox holds .git read-only and a fetch opens FETCH_HEAD for writing before it reads anything.
READONLY="$TEST_TMPDIR/readonly"
make_forge readonly --no-pr
chmod -R a-w "$READONLY/.git"
out=$(cd "$READONLY" && PATH="$READONLY/.git/eval-forge/bin:$PATH" git fetch origin main 2>&1)
assert_exit "read-only .git: git fetch exits 0 ($out)" 0 "$?"
chmod -R u+w "$READONLY/.git"

# --no-pr: the create phase's path. No PR until `pr create`, which takes the body file and opens it.
CREATE="$TEST_TMPDIR/create"
make_forge create --no-pr
CREATE_FORGE="$CREATE/.git/eval-forge"
assert_eq "--no-pr: the head is on origin, so a run's push has nothing to send" \
  "$(git -C "$CREATE" rev-parse feat/x)" "$(git -C "$CREATE_FORGE/eval-fixture/app.git" rev-parse feat/x)"
run_gh "$CREATE" pr view >/dev/null 2>&1
assert_exit "--no-pr: pr view finds no PR before create" 1 "$?"
assert_eq "--no-pr: pr list is empty before create" "0" "$(run_gh "$CREATE" pr list --head feat/x --json number --jq length)"
printf 'Refs: #5\n\n## Summary\n\nx\n' >"$TEST_TMPDIR/body.md"
out=$(run_gh "$CREATE" pr create --draft --head feat/x --title "feat: y" --body-file "$TEST_TMPDIR/body.md" 2>&1)
assert_eq "pr create: prints the new PR's URL" "https://github.com/eval-fixture/app/pull/7" "$out"
# Before the pr view below: that read is recorded too, as the last line.
assert_eq "pr create: the call is recorded" '"pr create"' "$(tail -n 1 "$CREATE_FORGE/calls.jsonl" | jq -c .command)"
assert_eq "pr create: the body file is kept for a grader" "$(cat "$TEST_TMPDIR/body.md")" "$(cat "$CREATE_FORGE/pr-body.md")"
assert_eq "pr create: the PR then reads as an open draft with the given title" "true feat: y" \
  "$(run_gh "$CREATE" pr view 7 --json isDraft,title --jq '"\(.isDraft) \(.title)"')"
run_gh "$CREATE" pr create --head feat/x --title again >/dev/null 2>&1
assert_exit "pr create: a second create for the branch is refused" 1 "$?"
out=$(run_gh "$CREATE" pr ready 7)
assert_eq "pr ready: flips the created draft" "false" "$(run_gh "$CREATE" pr view 7 --json isDraft --jq .isDraft)"

# Issues from issues/<n>.json, over GraphQL-shaped `issue view` and REST.
printf '{"number":5,"title":"t","state":"OPEN","body":"b","subIssues":{"nodes":[{"number":6,"title":"s","state":"OPEN"}]},"url":"https://github.com/eval-fixture/app/issues/5"}\n' \
  >"$CREATE_FORGE/issues/5.json"
assert_eq "issue view: state and body from the fixture" "OPEN b" "$(run_gh "$CREATE" issue view 5 --json state,body --jq '"\(.state) \(.body)"')"
run_gh "$CREATE" issue view 9 --json state >/dev/null 2>&1
assert_exit "issue view: an issue with no fixture exits 1" 1 "$?"
assert_eq "api issues: REST reports the state in lower case" "open" "$(run_gh "$CREATE" api "repos/{owner}/{repo}/issues/5" --jq .state)"
assert_eq "api sub_issues: lists the open sub-issue" "6 open" "$(run_gh "$CREATE" api repos/eval-fixture/app/issues/5/sub_issues --jq '.[] | "\(.number) \(.state)"')"
assert_eq "api repos: the default branch is the base" "main" "$(run_gh "$CREATE" api "repos/{owner}/{repo}" --jq .default_branch)"
assert_eq "api contents: a file at the base ref is served raw" "a" \
  "$(run_gh "$CREATE" api "repos/eval-fixture/app/contents/f?ref=main" -H "Accept: application/vnd.github.raw")"
run_gh "$CREATE" api "repos/eval-fixture/app/contents/docs/conventions/source-control.yaml?ref=main" >/dev/null 2>&1
assert_exit "api contents: a missing file is a 404, exit 1" 1 "$?"
run_gh "$CREATE" api --method POST repos/eval-fixture/app/pulls -f title=x >/dev/null 2>&1
assert_exit "api: a write method is refused" 1 "$?"

# --dir and --extra-pr: a forge installed into a checkout below the launch directory, serving two PRs.
MULTI="$TEST_TMPDIR/multi"
mkdir -p "$MULTI/app"
(
  cd "$MULTI/app" || exit 1
  git init -q -b main
  git config user.name eval
  git config user.email eval@example.invalid
  echo a >f
  git add f
  git commit -q -m seed
  for b in one two; do
    git checkout -q -b "fix/$b" main
    echo "$b" >f
    git commit -q -am "$b"
  done
  git checkout -q main
  cd "$MULTI" || exit 1
  bash "$SCRIPT_DIR/fixtures/gh-forge/install.sh" 61 fix/one main "fix: one" --open --extra-pr 62 fix/two "fix: two" --dir app
) >/dev/null 2>&1
assert_exit "install.sh --dir app --extra-pr: exit 0" 0 "$?"
assert_eq "pr list: the first and the extra pull request are served" "61 fix/one,62 fix/two" \
  "$(run_gh "$MULTI/app" pr list --json number,headRefName --jq 'map("\(.number) \(.headRefName)") | join(",")')"
assert_eq "pr view: the extra pull request by number, open like the first" "fix: two false" \
  "$(run_gh "$MULTI/app" pr view 62 --json title,isDraft --jq '"\(.title) \(.isDraft)"')"
run_gh "$MULTI/app" pr merge 62 --squash >/dev/null 2>&1
assert_eq "pr merge: the extra pull request's number is recorded" 62 \
  "$(tail -n 1 "$MULTI/app/.git/eval-forge/calls.jsonl" | jq .pr)"
(cd "$MULTI/app" && git fetch origin fix/two) >/dev/null 2>&1
assert_exit "git fetch origin with the stand-in off PATH: the alias runs the helper" 0 "$?"

for cmd in "pr close 7" "repo list" "api repos/eval-fixture/other" "auth switch" "run download 1" "gist create"; do
  # shellcheck disable=SC2086 # word splitting of the command words is intended
  run_gh "$THREADED" $cmd >/dev/null 2>&1
  assert_exit "unlisted command '$cmd' exits 1" 1 "$?"
done

echo
if ((FAILED)); then
  echo "Results: $FAILED of $CASE_NUM failed"
  exit 1
fi
echo "Results: $CASE_NUM passed"
