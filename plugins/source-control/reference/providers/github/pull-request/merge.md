# GitHub: pull-request merge

The GitHub commands behind the pull-request skill's
[merge phase](../../../../skills/pull-request/reference/merge.md). The phase owns every condition,
hold and ordering; this file holds the commands and the GitHub and `gh` facts behind them.

## Re-check checks and comments before merge

```bash
# 1. Re-check all check runs for any state changes
gh pr checks <pr_number> --json name,state,bucket

# 2. Re-check for new comments since monitoring completed (all 3 sources, paginated)
gh api --paginate "repos/{owner}/{repo}/pulls/<pr_number>/reviews?per_page=100" | jq -r '.[].user.login'
gh api --paginate "repos/{owner}/{repo}/pulls/<pr_number>/comments?per_page=100" | jq -r '.[].user.login'
gh api --paginate "repos/{owner}/{repo}/issues/<pr_number>/comments?per_page=100" | jq -r '.[].user.login'
```

## Stale-base guard

Read the head once and use that value for both the compare and `HEAD_SHA`, so the pinned head is
the one the compare checked:

```bash
read -r MSS BASE HEAD_SHA <<<"$(gh pr view <pr_number> --json mergeStateStatus,baseRefName,headRefOid \
  --jq '"\(.mergeStateStatus) \(.baseRefName) \(.headRefOid)"')"
echo "mergeStateStatus: $MSS"
gh api "repos/{owner}/{repo}/compare/$BASE...$HEAD_SHA"
```

When GraphQL is refused, read `.base.ref` and `.head.sha` from one
`gh api "repos/{owner}/{repo}/pulls/<pr_number>"` call instead.

Update a behind branch with a merge-forward or `gh pr update-branch`.

## Behind-branch exceptions

A base uses a merge queue when its branch rules carry a `merge_queue` rule; skip the update there:

```bash
gh api --paginate --slurp "repos/{owner}/{repo}/rules/branches/$BASE" \
  | jq -e 'add | any(.[]; .type == "merge_queue")' >/dev/null && echo 'merge queue: skip the update'
```

A dependency manager's PR shows its app login as the author (`app/dependabot`, `app/renovate`):

```bash
gh pr view <pr_number> --json author --jq .author.login
```

For Dependabot, request the rebase with a comment, never `gh pr update-branch` or a push:

```bash
gh pr comment <pr_number> --body '@dependabot rebase'
```

For another manager, use its own documented rebase trigger.

- **Pointer**: what a queue tests, under
  [about merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue#about-merge-queues);
  why extra commits are off limits, under
  [allowing Dependabot to rebase and force push over extra commits](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/managing-pull-requests-for-dependency-updates#allowing-dependabot-to-rebase-and-force-push-over-extra-commits);
  the comment commands, under
  [managing Dependabot pull requests with comment commands](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/managing-pull-requests-for-dependency-updates#managing-dependabot-pull-requests-with-comment-commands).
- **As of**: 2026-10-16
- **Recheck trigger**: the merge-queue section changing what a queue tests, or either Dependabot
  section changing how it treats extra commits or renaming the rebase comment command.

## Wait for a known merge state

GitHub reports `mergeStateStatus` as `UNKNOWN` while it recomputes it after a push or a ready flip,
and `gh pr merge` on a merge-queue base run then arms auto-merge instead of enqueueing. Poll at the
pinned head while it reads `UNKNOWN`; go on only on `CLEAN`:

```bash
: "${HEAD_SHA:?set HEAD_SHA in 4.1 step 2}"
for _ in $(seq 20); do
  S=$(gh pr view <pr_number> --json headRefOid,mergeStateStatus \
    --jq "if .headRefOid == \"$HEAD_SHA\" then .mergeStateStatus else \"HEAD_MOVED\" end")
  [ "$S" = UNKNOWN ] || break
  sleep 15
done
[ "$S" = CLEAN ] || { echo "PR reads ${S:-nothing} at the pinned head, not CLEAN: hold" >&2; exit 1; }
```

When GraphQL is refused, poll `.mergeable_state` from `gh api "repos/{owner}/{repo}/pulls/<pr_number>"`
(after checking `.head.sha` equals `HEAD_SHA`) while it reads `unknown`, and go on only on `clean`.
`mergeStateStatus` values:
[MergeStateStatus enum](https://docs.github.com/graphql/reference/enums#mergestatestatus), as of
2026-10-13; recheck when that enum changes.

## Squash merge in a regular checkout

```bash
gh pr merge <pr_number> --squash --delete-branch --match-head-commit "$HEAD_SHA"
```

## Squash merge in a linked worktree

Omit `--delete-branch`: on older gh it tries to check out the default branch locally, which fails
while another worktree holds it, and exits 1 even though the merge succeeded.

```bash
gh pr merge <pr_number> --squash --match-head-commit "$HEAD_SHA" && {
  if [ "$(gh pr view <pr_number> --json state -q .state)" = MERGED ]; then
    REMOTE=$(bash "<skill-dir>/scripts/resolve-remote.sh" --push '<branch>') && git push "$REMOTE" --delete --end-of-options '<branch>'
  else
    echo 'PR not merged yet (merge queue or auto-merge); delete the head branch once it reads MERGED' >&2
  fi
}
```

Verified 2026-09-29 against [cli/cli#14007](https://github.com/cli/cli/pull/14007), which ships in
gh 2.99.0 and makes `gh pr merge --delete-branch` skip the local delete when the head is checked out
in the current linked worktree; earlier gh, such as 2.98.0, fails as described. Recheck when the
minimum gh this plugin supports is 2.99.0 or later, at which point the split is no longer needed.

## Async merge API

`gh pr merge` and `gh pr view` run over GraphQL; the async merge API is REST. `gh` has no command
for it yet, so call it with `gh api`, pinned to the head verified before merge and never with
`bypass_rules` true:

```bash
: "${HEAD_SHA:?set HEAD_SHA in 4.1 step 2}"
gh api -X PUT "repos/{owner}/{repo}/pulls/<pr_number>/merge-async" \
  -f sha="$HEAD_SHA" -f merge_action=direct_merge -f merge_method=squash -F bypass_rules=false
```

For a merge queue send `-f merge_action=merge_queue` and drop `merge_method`. The response carries a
request `uuid` (a 409 means one is already pending and returns its `uuid`); poll
`gh api "repos/{owner}/{repo}/pulls/<pr_number>/merge-async/<uuid>" --jq .status` until it reads
`merged`, `enqueued`, or `failed`. Request fields and statuses:
[merge a pull request asynchronously](https://docs.github.com/rest/pulls/pulls?apiVersion=2026-03-10#merge-a-pull-request-asynchronously),
as of 2026-10-02; recheck when a `gh` release adds a command for it or that page changes a field or
status.

## Merge after AI review

```bash
[ "$(gh repo view --json owner --jq .owner.login)" = melodic-software ] \
  || { echo 'not a melodic-software repository: wait for the user' >&2; exit 1; }
: "${HEAD_SHA:?set HEAD_SHA in 4.1 step 2}"
RULES=$(gh api --paginate --slurp "repos/{owner}/{repo}/rules/branches/<baseRefName>" | jq 'add')
jq -e 'any(.[]; .type == "required_status_checks"
  and any(.parameters.required_status_checks[]; .context == "ci-status"))' <<<"$RULES" >/dev/null \
  || { echo 'base ruleset does not require ci-status: wait for the user' >&2; exit 1; }
RUNS=$(gh api --paginate --slurp "repos/{owner}/{repo}/commits/$HEAD_SHA/check-runs?per_page=100")
jq -e '[.[].check_runs[]] as $r
  | def lane($names): [$r[] | select(.name | IN($names[]))]
      | length > 0 and all(.status == "completed" and .conclusion == "success");
  ($r | length) == .[0].total_count
  and lane(["pr-review / claude-review-status"])
  and lane(["pr-review-security / security-review", "security-review / security-review",
            "claude-security-review-status"])' <<<"$RUNS" >/dev/null \
  || { echo 'AI review not complete on the pinned head: hold' >&2; exit 1; }
for _ in $(seq 20); do
  S=$(gh pr view <pr_number> --json headRefOid,mergeStateStatus \
    --jq "if .headRefOid == \"$HEAD_SHA\" then .mergeStateStatus else \"HEAD_MOVED\" end")
  [ "$S" = UNKNOWN ] || break
  sleep 15
done
[ "$S" = CLEAN ] || { echo "PR reads ${S:-nothing} at the pinned head, not CLEAN: hold" >&2; exit 1; }
if jq -e 'any(.[]; .type == "merge_queue")' <<<"$RULES" >/dev/null; then
  echo "merge-ready $HEAD_SHA queue"
else
  echo "merge-ready $HEAD_SHA squash"
fi
```

The script does not merge. When it prints `merge-ready <sha> <queue|squash>`, run the merge as its
own Bash command in the shape below, with nothing chained before it and every value written
literally: the PR number, `-R <owner>/<repo>`, your own login (`gh api user --jq .login`) and the
full 40-character sha the script printed, never a variable, a command substitution or a loop. The
guard re-checks the head, author, fork, draft, changed files, review checks (none failed) and
`ci-status` inside the command that merges, so an auto-mode allow entry that requires that guard
can match it, and a check rerun after the script cannot slip a failed review or an armed auto-merge
past it. Add `--squash` only
when the script printed `squash`; behind a merge queue the queue sets the strategy. Keep each
`|not` clause in its parentheses: jq's `|` binds looser than `and`, so without them a wrong head
would pass.

```bash
gh pr view <pr_number> -R <owner>/<repo> --json headRefOid,author,isCrossRepository,isDraft,files,statusCheckRollup --jq '.headRefOid=="<sha>" and .author.login=="<login>" and (.isCrossRepository|not) and (.isDraft|not) and ([.files[].path|select(test("^\\.github/(workflows|actions)/|(^|/)\\.claude/|(^|/)dot_claude/|^\\.chezmoi(data|templates)/|(^|/)(CLAUDE|AGENTS)\\.md(\\.tmpl)?$"))]|length==0) and ([.statusCheckRollup[]|select((.name//"")|test("review"))] as $r|($r|length>0) and ($r|all(.status=="COMPLETED")) and ($r|group_by(.workflowName)|all(any(.[]; .conclusion!="SKIPPED")))) and ([.statusCheckRollup[]|select((.name//"")|test("review"))]|all(.conclusion|IN("SUCCESS","SKIPPED"))) and ([.statusCheckRollup[]|select(.name=="ci-status")]|length>0 and (max_by(.completedAt).conclusion=="SUCCESS"))' | grep -qx true && gh pr merge <pr_number> -R <owner>/<repo> --squash --match-head-commit <sha>
```

Where the user's own instructions authorize an admin merge for that repository (a required
code-owner review or a merge queue blocks an otherwise ready merge), use this form instead, and
only it. It carries exactly `--squash`, `--admin` and `--match-head-commit`, never
`--delete-branch`:

```bash
gh pr view <pr_number> -R <owner>/<repo> --json headRefOid,mergeStateStatus,statusCheckRollup,files --jq '.headRefOid=="<sha>" and .mergeStateStatus!="DIRTY" and ([.statusCheckRollup[]|select(.name=="ci-status")]|length>0 and (max_by(.completedAt).conclusion=="SUCCESS")) and all(.statusCheckRollup[]; (.status//"COMPLETED")=="COMPLETED" and (.state//"")!="PENDING") and ([.files[].path|select(test("^\\.github/(workflows|actions)/|(^|/)\\.claude/|(^|/)dot_claude/|^\\.chezmoi(data|templates)/|(^|/)(CLAUDE|AGENTS)\\.md(\\.tmpl)?$"))]|length==0) and ([.statusCheckRollup[]|select((.name//"")|test("review"))] as $r|($r|length>0) and ($r|group_by(.workflowName)|all(any(.[]; .conclusion!="SKIPPED"))) and ($r|all(.conclusion|IN("SUCCESS","SKIPPED")))) and all(.statusCheckRollup[]; (.conclusion//.state//"")|IN("SUCCESS","SKIPPED","NEUTRAL"))' | grep -qx true && gh pr merge <pr_number> -R <owner>/<repo> --squash --admin --match-head-commit <sha>
```

A merge the permission layer refuses in this shape is a hand-off to the user, not a retry in
another shape. `grep -qx true` exits non-zero when the guard fails, which is a hold: re-read the PR
before anything else.

Behind a merge queue `gh pr merge` should enqueue and return; had required checks not passed it
would arm auto-merge instead. It has also been seen to return with a `CLEAN` PR left out of the
queue, so [confirm queue entry](#confirm-queue-entry) before the poll.

### Poll the merge queue

```bash
while :; do
  S=$(gh api graphql -F owner='{owner}' -F name='{repo}' -F number=<pr_number> -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) { state isInMergeQueue } } }' \
    --jq '.data.repository.pullRequest | "\(.state) \(.isInMergeQueue)"')
  case "$S" in
    MERGED*) break ;;
    'OPEN true') sleep 30 ;;
    *) echo "PR left the merge queue unmerged ($S)" >&2; exit 1 ;;
  esac
done
```

- **Pointer**: how `gh pr merge` behaves on a merge-queue base and what `--match-head-commit` does:
  [gh pr merge](https://cli.github.com/manual/gh_pr_merge); `isInMergeQueue`:
  [GraphQL PullRequest object](https://docs.github.com/graphql/reference/objects#pullrequest).
- **As of**: 2026-10-09
- **Recheck trigger**: a gh release that changes `gh pr merge` flags or merge-queue handling, or a
  rename of the AI review lanes' check names.

## Confirm queue entry

Read the PR's queue state. The script prints `merged`, `queued` or `enqueue <node id>`, or exits 1
with the hold:

```bash
: "${HEAD_SHA:?set HEAD_SHA in 4.1 step 2}"
for _ in $(seq 20); do
  PR=$(gh api graphql -F owner='{owner}' -F name='{repo}' -F number=<pr_number> -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        id state isInMergeQueue mergeStateStatus headRefOid autoMergeRequest { enabledAt } } } }' \
    --jq '.data.repository.pullRequest') || exit 1
  [ "$(jq -r .mergeStateStatus <<<"$PR")" = UNKNOWN ] || break
  sleep 15
done
AUTO=$(jq -r '.autoMergeRequest != null' <<<"$PR")
[ "$AUTO" = true ] && echo 'auto-merge is armed on this PR; tell the user (4.2.1 never arms it)' >&2
hold() {
  echo "$1" >&2
  [ "$AUTO" = true ] && echo 'auto-merge is still armed: a later push could merge on ci-status alone.
The user may disarm it with: gh pr merge <pr_number> --disable-auto' >&2
  exit 1
}
case "$(jq -r '"\(.state) \(.isInMergeQueue) \(.mergeStateStatus)"' <<<"$PR")" in
  MERGED*) echo 'merged' ;;
  'OPEN true '*)
    [ "$(jq -r .headRefOid <<<"$PR")" = "$HEAD_SHA" ] \
      || hold 'queued at a head other than the one pinned in 4.1: hold and report it'
    echo 'queued' ;;
  'OPEN false CLEAN')
    [ "$(jq -r .headRefOid <<<"$PR")" = "$HEAD_SHA" ] \
      || hold 'head moved since 4.1: hold and re-run readiness'
    echo "enqueue $(jq -r .id <<<"$PR")" ;;
  *) hold "not queued and not CLEAN ($(jq -c '{state,isInMergeQueue,mergeStateStatus}' <<<"$PR")): report it" ;;
esac
```

On `enqueue <node id>`, run the mutation as its own command, with the printed node id and the
`HEAD_SHA` value written in as literals, never a variable or command substitution: the guardrails
merge guard reads the PR from a literal `PR_...` id and blocks a merge-queue mutation whose PR it
cannot resolve. Never pass `jump: true`.

```bash
gh api graphql --silent -F id='<pr_node_id>' -F head='<head_sha>' -f query='
  mutation($id: ID!, $head: GitObjectID!) {
    enqueuePullRequest(input: {pullRequestId: $id, expectedHeadOid: $head}) {
      mergeQueueEntry { position } } }'
```

A non-zero exit is the refusal; its error text is the blocker. Then re-run the read: `queued` is
the result, and `enqueue` again means the mutation returned but the PR is not in the queue, a hold.

- **Pointer**: a PR joins a queue through the merge button or auto-merge:
  [managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue);
  the mutation and its `expectedHeadOid` input:
  [enqueuePullRequest](https://docs.github.com/graphql/reference/mutations#enqueuepullrequest).
- **As of**: 2026-10-11
- **Recheck trigger**: a gh release that changes how `gh pr merge` enqueues, or a change to
  `enqueuePullRequest` or its input on that page.

## Latest run on the default branch

```bash
gh run list --branch "$DEFAULT_BRANCH" --limit 1 --json conclusion,displayTitle \
  --jq '.[0] | "\(.conclusion): \(.displayTitle)"'
```
