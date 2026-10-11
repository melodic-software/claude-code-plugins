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

```bash
gh pr view <pr_number> --json mergeStateStatus,baseRefName,headRefOid
gh api repos/{owner}/{repo}/compare/<baseRefName>...<headRefOid>
```

Update a behind branch with a merge-forward or `gh pr update-branch`.

## Squash merge in a regular checkout

```bash
gh pr merge <pr_number> --squash --delete-branch
```

## Squash merge in a linked worktree

Omit `--delete-branch`: on older gh it tries to check out the default branch locally, which fails
while another worktree holds it, and exits 1 even though the merge succeeded.

```bash
gh pr merge <pr_number> --squash && {
  if [ "$(gh pr view <pr_number> --json state -q .state)" = MERGED ]; then
    REMOTE=$(bash "<skill-dir>/scripts/resolve-remote.sh" --push <branch>) && git push "$REMOTE" --delete <branch>
  else
    echo 'PR not merged yet (merge queue or auto-merge); delete <branch> once it reads MERGED' >&2
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
HEAD_SHA=$(gh api "repos/{owner}/{repo}/pulls/<pr_number>" --jq .head.sha)
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
HEAD_SHA=$(gh api "repos/{owner}/{repo}/pulls/<pr_number>" --jq .head.sha)
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
[ "$(gh pr view <pr_number> --json headRefOid,mergeStateStatus \
  --jq "select(.headRefOid == \"$HEAD_SHA\") | .mergeStateStatus")" = CLEAN ] \
  || { echo 'PR not CLEAN at the pinned head: hold' >&2; exit 1; }
if jq -e 'any(.[]; .type == "merge_queue")' <<<"$RULES" >/dev/null; then
  gh pr merge <pr_number> --match-head-commit "$HEAD_SHA"
else
  gh pr merge <pr_number> --squash --match-head-commit "$HEAD_SHA"
fi
```

Behind a merge queue `gh pr merge` enqueues and returns; had required checks not passed it would arm
auto-merge instead, which the `CLEAN` read rules out.

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

## Latest run on the default branch

```bash
gh run list --branch "$DEFAULT_BRANCH" --limit 1 --json conclusion,displayTitle \
  --jq '.[0] | "\(.conclusion): \(.displayTitle)"'
```
