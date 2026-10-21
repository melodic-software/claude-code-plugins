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

A dependency manager's PR names its app as the author. The spelling depends on the source:
`gh pr view` and `gh pr list` print `app/dependabot`, and REST `.user.login` prints
`dependabot[bot]`. Match either form, as `is_dependency_author` in the babysit-prs engine does:

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
  [managing Dependabot pull requests with comment commands](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/managing-pull-requests-for-dependency-updates#managing-dependabot-pull-requests-with-comment-commands);
  the author spellings, from a probe of Dependabot PR melodic-software/claude-code-plugins#7492
  with `gh pr view 7492 --json author` and `gh api repos/{owner}/{repo}/pulls/7492 --jq .user.login`.
- **As of**: 2026-10-16
- **Recheck trigger**: the merge-queue section changing what a queue tests, either Dependabot
  section changing how it treats extra commits or renaming the rebase comment command, or a `gh`
  release changing how it prints a bot author.

## Wait for a known merge state

GitHub reports `mergeStateStatus` as `UNKNOWN` while it recomputes it after a push or a ready flip,
and `gh pr merge` on a merge-queue base run then arms auto-merge instead of enqueueing. Poll at the
pinned head over REST, at the [API budget](../README.md#api-budget)'s 60 s, while it reads
`unknown`; go on only on `clean`:

```bash
: "${HEAD_SHA:?set HEAD_SHA in 4.1 step 2}"
for _ in $(seq 5); do
  S=$(gh api "repos/{owner}/{repo}/pulls/<pr_number>" \
    --jq "if .head.sha == \"$HEAD_SHA\" then .mergeable_state else \"head_moved\" end") || exit 1
  [ "$S" = unknown ] || break
  sleep 60
done
[ "$S" = clean ] || { echo "PR reads ${S:-nothing} at the pinned head, not clean: hold" >&2; exit 1; }
```

`mergeable_state` is the REST form of GraphQL's `mergeStateStatus`, lowercased:
[MergeStateStatus enum](https://docs.github.com/graphql/reference/enums#mergestatestatus), as of
2026-10-13; recheck when that enum changes.

## Merge command

Merge with `gh pr merge <pr_number> -R <owner>/<repo>` plus the flags the repository needs:
`--squash` for a squash merge (none behind a merge queue, where the queue sets the strategy),
`--auto` on a merge-queue or auto-merge base, and `--admin` only where a required code-owner review
or a merge queue blocks an otherwise ready merge and the consumer's own policy allows an admin
merge for that repository. Write the PR number and `-R <owner>/<repo>` literally, never as a
variable, command substitution or loop: the guardrails merge guard reads the target from them and
blocks a merge whose target it cannot resolve. `--match-head-commit <sha>`, with the sha written
literally, makes GitHub refuse the merge if the head moved. It is optional for an immediate merge
and required with `--auto`, pinning the head the session reviewed: where the AI review checks are
not required checks, an armed auto-merge would otherwise merge a later push.

GitHub's rulesets and required checks, and the guardrails merge guard, are the merge gate. A merge
that GitHub or the permission layer refuses is reported with its error text, and the session moves
on to other work: never hand the user the command to run, and never retry the merge in another
shape.

## Squash merge in a regular checkout

```bash
gh pr merge <pr_number> -R <owner>/<repo> --squash --delete-branch
```

## Squash merge in a linked worktree

Omit `--delete-branch`: on older gh it tries to check out the default branch locally, which fails
while another worktree holds it, and exits 1 even though the merge succeeded.

```bash
gh pr merge <pr_number> -R <owner>/<repo> --squash
```

Then, as its own command, delete the remote head branch once the PR reads `MERGED`:

```bash
if [ "$(gh pr view <pr_number> -R <owner>/<repo> --json state -q .state)" = MERGED ]; then
  REMOTE=$(bash "<skill-dir>/scripts/resolve-remote.sh" --push '<branch>') && git push "$REMOTE" --delete --end-of-options '<branch>'
else
  echo 'PR not merged yet (merge queue or auto-merge); delete the head branch once it reads MERGED' >&2
fi
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
`gh api "repos/{owner}/{repo}/pulls/<pr_number>/merge-async/<uuid>" --jq .status` every 60 s until it reads
`merged`, `enqueued`, or `failed`. Request fields and statuses:
[merge a pull request asynchronously](https://docs.github.com/rest/pulls/pulls?apiVersion=2026-03-10#merge-a-pull-request-asynchronously),
as of 2026-10-02; recheck when a `gh` release adds a command for it or that page changes a field or
status.

## Merge after AI review

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || exit 1
[ "${REPO%%/*}" = melodic-software ] \
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
for _ in $(seq 5); do
  S=$(gh api "repos/{owner}/{repo}/pulls/<pr_number>" \
    --jq "if .head.sha == \"$HEAD_SHA\" then .mergeable_state else \"head_moved\" end") || exit 1
  [ "$S" = unknown ] || break
  sleep 60
done
[ "$S" = clean ] || { echo "PR reads ${S:-nothing} at the pinned head, not clean: hold" >&2; exit 1; }
MODE=squash
jq -e 'any(.[]; .type == "merge_queue")' <<<"$RULES" >/dev/null && MODE=queue
echo "merge-ready $HEAD_SHA $MODE"
```

The script does not merge. After `merge-ready <sha> <queue|squash>`, run the
[merge command](#merge-command) as its own Bash command with the PR number and repository written
in: `--squash` when the script printed `squash`, no strategy flag when it printed `queue`. To pin
the merge to the head the script checked, add `--match-head-commit` with the printed sha; with
`--auto` the pin is required.

Behind a merge queue `gh pr merge` should enqueue and return; had required checks not passed it
would arm auto-merge instead. It has also been seen to return with a `CLEAN` PR left out of the
queue, so [confirm queue entry](#confirm-queue-entry) before the poll.

### Poll the merge queue

The wait reads REST every 60 s: the PR's state, and its latest queue event
(`added_to_merge_queue` or `removed_from_merge_queue`). Only when that read changes does it read
`isInMergeQueue` over GraphQL, once, to decide:

```bash
while :; do
  while [ "$(gh api "repos/{owner}/{repo}/pulls/<pr_number>" --jq .state)" = open ] &&
    [ "$(gh api --paginate "repos/{owner}/{repo}/issues/<pr_number>/events?per_page=100" \
      --jq '.[] | select(.event | endswith("_merge_queue")) | .event' | tail -n 1)" = added_to_merge_queue ]; do
    sleep 60
  done
  S=$(gh api graphql -F owner='{owner}' -F name='{repo}' -F number=<pr_number> -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) { state isInMergeQueue } } }' \
    --jq '.data.repository.pullRequest | "\(.state) \(.isInMergeQueue)"') || exit 1
  case "$S" in
    MERGED*) break ;;
    'OPEN true') sleep 60 ;;
    *) echo "PR left the merge queue unmerged ($S)" >&2; exit 1 ;;
  esac
done
```

- **Pointer**: how `gh pr merge` behaves on a merge-queue base and what `--match-head-commit` does:
  [gh pr merge](https://cli.github.com/manual/gh_pr_merge); `isInMergeQueue`:
  [GraphQL PullRequest object](https://docs.github.com/graphql/reference/objects#pullrequest).
  The queue events: `GET repos/{owner}/{repo}/issues/{n}/events` returned `added_to_merge_queue`
  and `removed_from_merge_queue` for a queue-merged PR (melodic-software/claude-code-plugins#7771,
  read 2026-10-17), though [issue event types](https://docs.github.com/en/rest/using-the-rest-api/issue-event-types)
  does not list them.
- **As of**: 2026-10-09; queue events 2026-10-17
- **Recheck trigger**: a gh release that changes `gh pr merge` flags or merge-queue handling, a
  rename of the AI review lanes' check names, or the events endpoint no longer returning the queue
  events.

## Confirm queue entry

Read the PR's queue state. The script prints `merged`, `queued` or `enqueue <node id>`, or exits 1
with the hold:

```bash
: "${HEAD_SHA:?set HEAD_SHA in 4.1 step 2}"
for _ in $(seq 5); do
  [ "$(gh api "repos/{owner}/{repo}/pulls/<pr_number>" --jq .mergeable_state)" = unknown ] || break
  sleep 60
done
PR=$(gh api graphql -F owner='{owner}' -F name='{repo}' -F number=<pr_number> -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) { pullRequest(number: $number) {
      id state isInMergeQueue mergeStateStatus headRefOid autoMergeRequest { enabledAt } } } }' \
  --jq '.data.repository.pullRequest') || exit 1
AUTO=$(jq -r '.autoMergeRequest != null' <<<"$PR")
[ "$AUTO" = true ] && echo 'auto-merge is armed on this PR; report it' >&2
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
