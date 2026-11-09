#!/usr/bin/env bash
# Builds every pull-request-reassess-* case's state from its own scaffold and runs the action's limits read and
# forge commands against it. Expected limits come from the kinds table in skills/pull-request/reference/reassess.md;
# the commit-to-PR, comment and push expectations from each scaffold's stated state.

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALS="$SCRIPT_DIR"
LIMITS="$EVALS/../skills/pull-request/scripts/reassess-limits.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../scripts/test-helpers.sh
source "$EVALS/../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

scaffold() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir"
  (cd "$dir" && bash "$EVALS/pull-request-reassess-$1/scaffold.sh") >/dev/null 2>&1
  assert_exit "$1: scaffold exit 0" 0 "$?"
}

in_case() {
  local dir="$TEST_TMPDIR/$1"
  shift
  (cd "$dir" && PATH="$dir/.git/eval-forge/bin:$PATH" "$@")
}

limits() {
  in_case "$1" bash "$LIMITS" 512 --repo eval-fixture/app --state-dir "$TEST_TMPDIR/state" 2>&1
}

for c in close continue rework report-only no-goal close-label-first fork-no-push fork-close labeled-own-comment rebase-comparison; do
  scaffold "$c"
done

for c in close continue rework report-only no-goal close-label-first rebase-comparison; do
  out=$(limits "$c")
  assert_exit "$c: no limit, so a verdict and any action are open" 0 "$?"
  assert_eq "$c: the limits read prints nothing" "" "$out"
done

out=$(limits labeled-own-comment)
assert_exit "labeled: a limit" 3 "$?"
assert_eq "labeled: only the label limit" "label: the pull request carries do-not-merge" "$out"

out=$(limits fork-no-push)
assert_exit "fork: a limit" 3 "$?"
assert_eq "fork: only the no-update limit" "no-update: the head is on a fork" "$out"

out=$(limits fork-close)
assert_exit "fork close: a limit" 3 "$?"
assert_eq "fork close: only the no-update limit, which leaves a close free to act" "no-update: the head is on a fork" "$out"

# The fetch the action makes, through the helper.
ORIGIN="$TEST_TMPDIR/fork-no-push/.git/eval-forge/eval-fixture/app.git"
in_case fork-no-push git fetch -q origin "+refs/pull/512/head:refs/reassess/512-1" "+refs/heads/main:refs/remotes/origin/main" >/dev/null 2>&1
assert_exit "fork: the pull ref fetches" 0 "$?"
assert_eq "fork: the fetched ref is the forge's head" \
  "$(in_case fork-no-push gh pr view 512 --json headRefOid --jq .headRefOid)" "$(in_case fork-no-push git rev-parse refs/reassess/512-1)"
git -C "$ORIGIN" rev-parse -q --verify refs/heads/fix/retry-limit >/dev/null
assert_exit "fork: the head branch is not on the origin" 1 "$?"
assert_eq "fork: a cross-repository head" "true contributor/app" \
  "$(in_case fork-no-push gh api repos/eval-fixture/app/pulls/512 --jq '"true \(.head.repo.full_name)"')"

# Closing issue, goal, and the replaced-by search.
assert_eq "close: the closing issue" "eval-fixture/app 77" \
  "$(in_case close gh pr view 512 --json closingIssuesReferences -q '.closingIssuesReferences[] | "\(.repository.owner.login)/\(.repository.name) \(.number)"')"
assert_eq "close: the issue body serves" "OPEN" "$(in_case close gh issue view 77 --repo eval-fixture/app --json state --jq .state)"
assert_eq "close: an empty diff against main, as a merged-base head has" "0" \
  "$(in_case close gh pr view 512 --json files --jq '.files | length')"
LANDED=$(git -C "$TEST_TMPDIR/close" log main --format=%H --grep='(#501)')
assert_eq "close: the landed commit is the SHA the replaced-by grader names" 8ebb875 "${LANDED:0:7}"
assert_eq "close: the seed commit is the range start the base-range grader names" c02d2f9 \
  "$(git -C "$TEST_TMPDIR/close" log main --format=%h --abbrev=7 --grep='chore: seed')"
assert_eq "close: the base tip is the range end the base-range grader names" d0f728e \
  "$(git -C "$TEST_TMPDIR/close" rev-parse --short=7 main)"
assert_eq "close: the commit maps to PR 501, merged into main" "501 main" \
  "$(in_case close gh api "repos/eval-fixture/app/commits/$LANDED/pulls" --jq '.[] | select(.merged_at != null) | "\(.number) \(.base.ref)"')"
assert_eq "close: another commit maps to no PR" "0" \
  "$(in_case close gh api "repos/eval-fixture/app/commits/0000000/pulls" --jq length)"
assert_eq "close: the search for a body term finds the merged PR" "501" \
  "$(in_case close gh pr list -R eval-fixture/app --state all --limit 200 --search "HTTP 503 in:body" --json number,state,title,mergedAt --jq 'map(select(.number != 512)) | .[].number')"
assert_eq "close: a term in no body finds nothing" "0" \
  "$(in_case close gh pr list -R eval-fixture/app --state all --search "#999 in:body" --json number --jq length)"
assert_eq "close: the merged PR reads through pr view" "MERGED" "$(in_case close gh pr view 501 --json state --jq .state)"
assert_eq "no-goal: an empty body and nothing closed" " 0" \
  "$(in_case no-goal gh pr view 512 --json body,closingIssuesReferences --jq '"\(.body) \(.closingIssuesReferences | length)"')"

# Writes land in the call record, and a label edit is visible to the next read.
CALLS="$TEST_TMPDIR/close-label-first/.git/eval-forge/calls.jsonl"
in_case close-label-first gh pr edit 512 -R eval-fixture/app --add-label do-not-merge >/dev/null
assert_exit "pr edit: exit 0" 0 "$?"
assert_eq "pr edit: recorded with its arguments" \
  '{"command":"pr edit","pr":512,"args":["512","-R","eval-fixture/app","--add-label","do-not-merge"]}' "$(tail -n 1 "$CALLS")"
assert_eq "pr edit: the label reads back" "do-not-merge" "$(in_case close-label-first gh pr view 512 --json labels --jq '.labels[].name')"
assert_eq "label list: the hold label exists" "do-not-merge" "$(in_case close-label-first gh label list -R eval-fixture/app --limit 1000 --json name -q '.[].name')"

in_case close-label-first gh api --method PUT repos/eval-fixture/app/pulls/512/update-branch >/dev/null 2>&1
assert_exit "update-branch: refused" 1 "$?"
assert_eq "update-branch: the attempt is recorded" '"api PUT"' "$(tail -n 1 "$CALLS" | jq -c .command)"

in_case close-label-first gh pr update-branch 512 >/dev/null 2>&1
assert_exit "pr update-branch: refused" 1 "$?"
assert_eq "pr update-branch: the attempt is recorded" '"pr update-branch"' "$(tail -n 1 "$CALLS" | jq -c .command)"

in_case close-label-first gh pr close 512 >/dev/null 2>&1
assert_exit "pr close: refused" 1 "$?"
assert_eq "pr close: the attempt is recorded" '"pr close"' "$(tail -n 1 "$CALLS" | jq -c .command)"

in_case close-label-first gh api repos/eval-fixture/app/issues/512/comments -f body=x >/dev/null 2>&1
assert_exit "api with a field and no method: a POST, so refused" 1 "$?"
assert_eq "api with a field and no method: recorded as a POST" '"api POST"' "$(tail -n 1 "$CALLS" | jq -c .command)"
assert_eq "api -X GET with a field stays a read" "a read" \
  "$(in_case close-label-first gh api -X GET repos/eval-fixture/app/contents/README.md -f ref=main >/dev/null && echo 'a read')"

# Pushes go through the git stand-in on the case's PATH. The record shape is the one the graders read.
FORGE_ORIGIN="$TEST_TMPDIR/close-label-first/.git/eval-forge/eval-fixture/app.git"
CL_DIR="$TEST_TMPDIR/close-label-first"
MAIN_SHA=$(git -C "$CL_DIR" rev-parse main)
OLDER_SHA=$(git -C "$CL_DIR" rev-parse main~1)
PULL_BEFORE=$(git -C "$FORGE_ORIGIN" rev-parse refs/pull/512/head)
record_of() { printf '{"command":"push","ref":"%s","sha":"%s","forced":%s}' "$1" "$2" "$3"; }

in_case close-label-first git push -q origin main:refs/heads/probe >/dev/null 2>&1
assert_exit "push: accepted by the origin" 0 "$?"
assert_eq "push: an unforced push is recorded" "$(record_of refs/heads/probe "$MAIN_SHA" false)" "$(tail -n 1 "$CALLS")"
in_case close-label-first git push -q --force origin main~1:refs/heads/probe >/dev/null 2>&1
assert_eq "push: --force is recorded as forced" "$(record_of refs/heads/probe "$OLDER_SHA" true)" "$(tail -n 1 "$CALLS")"
in_case close-label-first git push -q origin +main:refs/heads/probe >/dev/null 2>&1
assert_eq "push: a + refspec is recorded as forced" "$(record_of refs/heads/probe "$MAIN_SHA" true)" "$(tail -n 1 "$CALLS")"
in_case close-label-first git push -qf origin main~1:refs/heads/probe >/dev/null 2>&1
assert_eq "push: a clustered -f is recorded as forced" "$(record_of refs/heads/probe "$OLDER_SHA" true)" "$(tail -n 1 "$CALLS")"

LINES=$(wc -l <"$CALLS")
in_case close-label-first git push -q origin refs/heads/no-such-branch:refs/heads/missing >/dev/null 2>&1
assert_exit "push: a failed push keeps git's exit status" 1 "$?"
assert_eq "push: a failed push records nothing" "$LINES" "$(wc -l <"$CALLS")"
in_case close-label-first git status --short >/dev/null
assert_eq "git: any other command records nothing" "$LINES" "$(wc -l <"$CALLS")"
assert_eq "push: a push to another branch leaves the pull ref" "$PULL_BEFORE" "$(git -C "$FORGE_ORIGIN" rev-parse refs/pull/512/head)"

in_case close-label-first git -c core.hooksPath=/dev/null push -q origin main:refs/heads/probe-no-hooks >/dev/null 2>&1
assert_exit "push: accepted with hooks disabled" 0 "$?"
assert_eq "push: recorded with hooks disabled, past a global option" "$(record_of refs/heads/probe-no-hooks "$MAIN_SHA" false)" "$(tail -n 1 "$CALLS")"

in_case close-label-first gh api graphql -f 'query=mutation { closePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }' >/dev/null 2>&1
assert_exit "graphql mutation: refused" 1 "$?"
assert_eq "graphql mutation: the attempt is recorded" '"api graphql mutation"' "$(tail -n 1 "$CALLS" | jq -c .command)"

mkdir -p "$TEST_TMPDIR/close-env"
(cd "$TEST_TMPDIR/close-env" && GIT_AUTHOR_NAME=other GIT_COMMITTER_EMAIL=other@example.invalid bash "$EVALS/pull-request-reassess-close/scaffold.sh") >/dev/null 2>&1
assert_eq "close: the pinned SHAs ignore the operator's identity variables" "$(git -C "$TEST_TMPDIR/close" rev-parse main)" "$(git -C "$TEST_TMPDIR/close-env" rev-parse main)"

# The comment read and edit a re-run makes.
LABELED_CALLS="$TEST_TMPDIR/labeled-own-comment/.git/eval-forge/calls.jsonl"
assert_eq "comments: the newest own marked comment is 9001, not the other login's 9002" "9001" \
  "$(in_case labeled-own-comment gh api --paginate --slurp "repos/eval-fixture/app/issues/512/comments?per_page=100" | jq -r --arg login eval-fixture 'add // [] | map(select(.user.login == $login and (.body | startswith("<!-- source-control-reassess -->")))) | last | .id')"
printf 'edited body\n' >"$TEST_TMPDIR/body"
in_case labeled-own-comment gh api --method PATCH repos/eval-fixture/app/issues/comments/9001 -F "body=@$TEST_TMPDIR/body" >/dev/null
assert_exit "comment edit: exit 0" 0 "$?"
assert_eq "comment edit: recorded with the id and the body" \
  '{"command":"comment edit","pr":512,"args":["9001","edited body"]}' "$(tail -n 1 "$LABELED_CALLS")"
in_case labeled-own-comment gh api --method PATCH repos/eval-fixture/app/issues/comments/1 -F "body=@$TEST_TMPDIR/body" >/dev/null 2>&1
assert_exit "comment edit: an unseeded id is refused" 1 "$?"

assert_eq "merge queue: never in one" "false" "$(in_case close gh api graphql -F owner=eval-fixture -F name=app -F number=512 -f 'query=query { isInMergeQueue }' --jq .data.repository.pullRequest.isInMergeQueue)"

# The action's other reads, each answered offline.
assert_eq "rest: inline comments, as one empty page" "[[]]" \
  "$(in_case close gh api --paginate --slurp 'repos/eval-fixture/app/pulls/512/comments?per_page=100' --jq tojson)"
assert_eq "rest: reviews with a query string, as one empty page" "[[]]" \
  "$(in_case close gh api --paginate --slurp 'repos/eval-fixture/app/pulls/512/reviews?per_page=100' --jq tojson)"
assert_eq "rest: no native stack" "no" \
  "$(in_case close gh api repos/eval-fixture/app/pulls/512 --jq 'if (.stack | type) == "object" then "yes" else "no" end')"
assert_eq "continue: the PR's file through REST" "src/retry.ts" \
  "$(in_case continue gh api repos/eval-fixture/app/pulls/512/files --jq '.[].filename')"
assert_eq "pr view commits: the head's commit" "fix: retry a failed request three times" \
  "$(in_case continue gh pr view 512 --json commits --jq '.commits[].messageHeadline')"

# The update decision's reads, from the unpopulated worktree the action uses, in a run whose only
# writable path is the workspace: worktreeroot.path keeps it inside.
ROOT=$(in_case continue git config worktreeroot.path)
assert_eq "worktree root: inside the checkout" "$TEST_TMPDIR/continue/.eval-worktrees" "$ROOT"
in_case continue git fetch -q origin "+refs/pull/512/head:refs/reassess/512-1" >/dev/null 2>&1
TREE="$ROOT/reassess-512"
in_case continue git -c core.hooksPath=/dev/null worktree add -q --detach --no-checkout "$TREE" refs/reassess/512-1 >/dev/null 2>&1
assert_exit "worktree: an unpopulated tree is added" 0 "$?"
SIGNALS=$(in_case continue bash -c "cd '$TREE' && bash '$EVALS/../scripts/branch-update-signals.sh' --pr 512 --repo eval-fixture/app")
assert_eq "signals: the head behind main and every read answered" "yes no" \
  "$(jq -r '"\(.behind) \(.conflict)"' <<<"$SIGNALS")"
assert_eq "signals: nothing unknown except a base change the action has no overlap read for" "" \
  "$(jq -r 'to_entries | map(select(.value == "unknown" and .key != "base_change_needed") | .key) | join(",")' <<<"$SIGNALS")"

# The rebase path: the decision from the session's own checkout, then section 4 of the action run by
# hand. The method and rule come from the rows in branch-update-method.sh, the steps from
# ready-for-review.md "Carry out a rebase".
HEAD_BRANCH=fix/retry-limit
REBASE_DIR="$TEST_TMPDIR/rebase-comparison"
REBASE_CALLS="$REBASE_DIR/.git/eval-forge/calls.jsonl"
METHOD="$EVALS/../scripts/branch-update-method.sh"
FORGE_HEAD=$(in_case rebase-comparison gh pr view 512 --json headRefOid --jq .headRefOid)
assert_eq "rebase: the session's checkout holds the head branch at the forge's head" \
  "$HEAD_BRANCH $FORGE_HEAD" "$(git -C "$REBASE_DIR" branch --show-current) $(git -C "$REBASE_DIR" rev-parse HEAD)"

SIGNALS=$(in_case rebase-comparison bash "$EVALS/../scripts/branch-update-signals.sh" --pr 512 --repo eval-fixture/app --allow-rewrite)
DECISION=$(bash "$METHOD" <<<"$SIGNALS")
assert_eq "rebase: the base's setting forces a rebase over the human-reviewed row" "rebase human-reviewed true yes" \
  "$(jq -r '"\(.method) \(.rule) \(.setting.applied) \(.human_review)"' <<<"$DECISION")"
assert_eq "rebase: the decision pins the forge's head" "$FORGE_HEAD" "$(jq -r .head_sha <<<"$DECISION")"
assert_eq "rebase: with the setting left at auto the same signals give a merge" "merge human-reviewed" \
  "$(jq '.setting = "auto"' <<<"$SIGNALS" | bash "$METHOD" | jq -r '"\(.method) \(.rule)"')"
assert_eq "rebase: without --allow-rewrite the head cannot be rewritten" "merge no-rewrite" \
  "$(in_case rebase-comparison bash "$EVALS/../scripts/branch-update-signals.sh" --pr 512 --repo eval-fixture/app | bash "$METHOD" | jq -r '"\(.method) \(.rule)"')"

people_read() {
  in_case "$1" gh api --paginate --slurp "repos/{owner}/{repo}/pulls/512/reviews" | jq 'add // [] | map(select(.user.type != "Bot")) | length'
}
assert_eq "rebase: the reviewer read finds the person's review" 1 "$(people_read rebase-comparison)"
assert_eq "continue: the reviewer read finds none on a PR nobody reviewed" 0 "$(people_read continue)"

assert_eq "rebase: the push checks name the remote and the branch" "$(printf 'origin\t%s' "$HEAD_BRANCH")" \
  "$(in_case rebase-comparison bash "$EVALS/../skills/pull-request/scripts/push-branch.sh" --preflight --pr 512)"
in_case rebase-comparison git fetch -q origin "+refs/heads/$HEAD_BRANCH:refs/remotes/origin/$HEAD_BRANCH" "+refs/heads/main:refs/remotes/origin/main" >/dev/null 2>&1
assert_exit "rebase: the head and the base fetch" 0 "$?"
LEASE=$(git -C "$REBASE_DIR" rev-parse "refs/remotes/origin/$HEAD_BRANCH")
assert_eq "rebase: the lease is the decision's head" "$FORGE_HEAD" "$LEASE"
in_case rebase-comparison git switch -q --detach >/dev/null 2>&1
in_case rebase-comparison git rebase -q --no-update-refs origin/main >/dev/null 2>&1
assert_exit "rebase: a detached rebase onto the base has no conflict" 0 "$?"
RANGE_DIFF=$(git -C "$REBASE_DIR" range-diff origin/main "$LEASE" HEAD)
grep -Eq '^ *1: +[0-9a-f]{7,} += +1: +[0-9a-f]{7,}' <<<"$RANGE_DIFF"
assert_exit "rebase: the range-diff pairs the rewritten commit with the original" 0 "$?"
in_case rebase-comparison git push -q "--force-with-lease=$HEAD_BRANCH:$LEASE" origin "HEAD:refs/heads/$HEAD_BRANCH" >/dev/null 2>&1
assert_exit "rebase: the pinned force push is accepted" 0 "$?"
assert_eq "rebase: the push is recorded as a rewrite of the head branch" "push refs/heads/$HEAD_BRANCH true" \
  "$(tail -n 1 "$REBASE_CALLS" | jq -r '"\(.command) \(.ref) \(.forced)"')"
assert_eq "rebase: the forge's head follows the push" \
  "$(git -C "$REBASE_DIR" rev-parse HEAD)" "$(in_case rebase-comparison gh pr view 512 --json headRefOid --jq .headRefOid)"
assert_eq "rebase: the pull ref moved with the push" \
  "$(git -C "$REBASE_DIR" rev-parse HEAD)" "$(git -C "$REBASE_DIR/.git/eval-forge/eval-fixture/app.git" rev-parse refs/pull/512/head)"
in_case rebase-comparison git push -q "--force-with-lease=$HEAD_BRANCH:$LEASE" origin "$LEASE:refs/heads/$HEAD_BRANCH" >/dev/null 2>&1
assert_exit "rebase: a push under the old lease is rejected" 1 "$?"
printf '%s\n' "$RANGE_DIFF" | in_case rebase-comparison gh pr comment 512 --body-file - >/dev/null
assert_exit "rebase: the comparison posts" 0 "$?"
assert_eq "rebase: the only writes are the push, then the comment" "push,pr comment" \
  "$(jq -sr 'map(select(.command != "read") | .command) | join(",")' "$REBASE_CALLS")"
assert_eq "rebase: the comment body is kept for the grader" "$RANGE_DIFF" "$(cat "$REBASE_DIR/.git/eval-forge/comment-body.md")"

in_case close gh pr comment 512 --body 'plain body' >/dev/null
assert_eq "pr comment: a --body body is kept too" "plain body" "$(cat "$TEST_TMPDIR/close/.git/eval-forge/comment-body.md")"

in_case rework git merge-tree --write-tree --quiet fix/user-retry main >/dev/null 2>&1
assert_exit "rework: the head merges with main without a conflict" 0 "$?"

echo
if ((FAILED)); then
  echo "Results: $FAILED of $CASE_NUM failed"
  exit 1
fi
echo "Results: $CASE_NUM passed"
