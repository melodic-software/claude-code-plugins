# GitHub: pull-request ready for review

The GitHub commands behind the pull-request skill's
[ready-for-review phase](../../../../skills/pull-request/reference/ready-for-review.md). The phase
owns the order, the gates and the completion criteria; this file holds the commands and the GitHub
and `gh` facts behind them.

## Find the PR for the branch

```bash
BRANCH=$(git branch --show-current)
PR_NUMBER=$(gh pr view "$BRANCH" --json number -q '.number' 2>/dev/null)
```

## Read the draft flag

```bash
gh pr view "$PR_NUMBER" --json isDraft -q '.isDraft'
```

## Check for a hold

```bash
bash "<skill-dir>/scripts/check-ready-holds.sh" "$PR_NUMBER"               # a person drives the run
bash "<skill-dir>/scripts/check-ready-holds.sh" "$PR_NUMBER" --unattended  # no person drives it
```

Exit 0: no hold. Exit 3: held or superseded, one reason per line on stdout. Exit 2: a `gh` read
or a parse failed, so no hold was ruled out. Exit 1: a bad argument. Exit 5: `gh` or `jq` is
missing. The script reads the title, body, labels and closing issue
references with `gh pr view`, and each closing issue's state over REST.

## Read the pre-ready steps at the base

The PR's own base branch, in the PR's own base repository. The repository comes from the PR's
URL, which names the base repository, never from gh's `{owner}/{repo}` default: in a fork
checkout with no upstream remote, that default resolves to the fork the PR's author controls.
`-f ref=` with `-X GET` sends the branch name as an encoded query parameter. `-i` puts the status
line on stdout, where the reader reads it: only a 404 means no file, and any other failure (auth,
5xx, no response) fails closed.

The reader honors the list only when the base is the base repository's default branch, read from
that same repository. A failed lookup leaves the value empty, and the reader fails closed on it:
on error `gh api` prints the error body to stdout, so each lookup clears its value on a non-zero
exit.

```bash
BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName') || BASE=""
BASE_REPO=$(gh pr view "$PR_NUMBER" --json url -q '.url | split("/")[3:5] | join("/")') || BASE_REPO=""
DEFAULT_BRANCH=$(gh api "repos/$BASE_REPO" --jq '.default_branch') || DEFAULT_BRANCH=""
PRE_READY_RESPONSE=$(gh api -i -X GET "repos/$BASE_REPO/contents/docs/conventions/source-control.yaml" \
  -f ref="$BASE" -H "Accept: application/vnd.github.raw")
printf '%s' "$PRE_READY_RESPONSE" |
  bash "<skill-dir>/scripts/read-pre-ready.sh" --base "$BASE" --default-branch "$DEFAULT_BRANCH" --http-response
```

On a 404, gh also prints `gh: Not Found (HTTP 404)` to stderr; that line is expected.

## Refresh the base with a merge

```bash
BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName')
REMOTE=$(bash "<skill-dir>/scripts/resolve-remote.sh") || exit 1

gh pr update-branch "$PR_NUMBER"                     # merges the base into the head branch
git fetch "$REMOTE" "$BRANCH" && git merge --ff-only FETCH_HEAD
```

When the head already contains the base tip, `gh pr update-branch` prints "PR branch already
up-to-date" and pushes nothing (cli/cli `pkg/cmd/pr/update-branch/update_branch.go`, the
`BehindBy == 0` return, read 2026-10-02; recheck when a gh release changes `update-branch`).

The PR's head commit, for the completion check:

```bash
gh pr view "$PR_NUMBER" --json headRefOid -q '.headRefOid'
```

## Read the diff

```bash
gh pr diff "$PR_NUMBER"
```

## Record the skipped steps

One conversation comment per run, after the hold re-check and right before the flip. One
`--step` per step `--skip` removed; the comment is built in full before it is posted, so a failed
build posts nothing:

```bash
LOGIN=$(gh api user --jq .login) || exit 1
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid -q '.headRefOid') || exit 1
COMMENT=$(bash "<skill-dir>/scripts/ready-skip-comment.sh" --login "$LOGIN" --head "$HEAD_SHA" \
  --reason "$REASON" --step code-review) || exit 1
printf '%s\n' "$COMMENT" | gh pr comment "$PR_NUMBER" --body-file -
```

`check-ready-holds.sh` reads the title, body, labels and closing issue references, never
comments, so the comment cannot set or lift a hold there.

## List the workflow runs for the head

Both steps below read the runs registered for one head commit. `head_sha` and `event` are query
parameters of the list-workflow-runs endpoint, `head_sha` returning only runs associated with that
commit, and a run's `status` and `conclusion` take the values the endpoint's `status` parameter
lists, `skipped` among them (read 2026-10-18 at
<https://docs.github.com/en/rest/actions/workflow-runs>, "List workflow runs for a repository").
`$HEAD_SHA` is the PR's head commit from "Refresh the base with a merge".

```bash
gh api -X GET "repos/{owner}/{repo}/actions/runs" -f head_sha="$HEAD_SHA" -f event=pull_request \
  -f per_page=100 --jq '.workflow_runs[] | [.id, .created_at, .status, .conclusion // ""] | @tsv'
```

Each row is `id`, `created_at`, `status` and `conclusion`, the conclusion empty until the run
completes. A `{owner}/{repo}` placeholder resolves from the checkout's remote, so in a fork checkout
substitute the base repository from the PR's URL, as "Read the pre-ready steps at the base" does.

## Wait for the head's runs to register

Run it after the last push and before the flip. It polls the listing above every 10 seconds for up
to 120 seconds and stops at the first row; no row by then is not an error, only a note in the
report:

```bash
for _ in $(seq 1 12); do
  ROWS=$(gh api -X GET "repos/{owner}/{repo}/actions/runs" -f head_sha="$HEAD_SHA" \
    -f event=pull_request --jq '.workflow_runs | length') || ROWS=0
  [ "${ROWS:-0}" -gt 0 ] && break
  sleep 10
done
```

## Check the head's lanes after the flip

Take `FLIP_TIME` (UTC, `date -u +%Y-%m-%dT%H:%M:%SZ`) right before the flip. After it, poll the
listing for up to 180 seconds for a run created at or after `FLIP_TIME`, the `ready_for_review`
run. Once every such run has completed, a `skipped` conclusion among them means the lanes skipped
on a stale draft payload; no run created at or after `FLIP_TIME` by the end of the wait is also a
skip, since the flip's run never registered:

```bash
RUNS=$(gh api -X GET "repos/{owner}/{repo}/actions/runs" -f head_sha="$HEAD_SHA" -f event=pull_request \
  -f per_page=100 | jq -c --arg t "$FLIP_TIME" '[.workflow_runs[] | select(.created_at >= $t)]')
```

Re-fire the ready event once with `gh pr ready "$PR_NUMBER" --undo && gh pr ready "$PR_NUMBER"`,
then run this check one more time against a new `FLIP_TIME`. A second skip is reported, never
re-fired.

## Flip to ready

```bash
gh pr ready "$PR_NUMBER"
```

In a cloud session `gh pr ready` fails, because the flip is a GraphQL mutation. The proxy's REST
route:

```bash
gh api --method POST "repos/{owner}/{repo}/pulls/$PR_NUMBER/ccr/ready_for_review"
```

Or the GitHub MCP `update_pull_request` call with `draft: false`.
