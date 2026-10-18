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

## Record the head before the refresh

Run the wait, flip and confirm blocks below in the same shell as this one, since they share
`HEAD_BEFORE`, `HEAD_SHA`, `CI_WORKFLOW`, `RUNS_BEFORE` and `ready_run_seen`. When 2.5.2 is skipped,
still run this line, before the push.

```bash
HEAD_BEFORE=$(gh pr view "$PR_NUMBER" --json headRefOid -q '.headRefOid') || exit 1
```

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

## Wait for the push's CI run

`CI_WORKFLOW` is the repository's CI workflow file (`ci.yml` here). Skip the wait when the head is
unchanged, but still run the first two assignments, which the flip block reads. A run listed for the head SHA means the push's event reached the workflow; the wait
does not look at the run's result.

```bash
CI_WORKFLOW=ci.yml
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid -q '.headRefOid') || exit 1
if [ "$HEAD_SHA" != "$HEAD_BEFORE" ]; then
  FOUND=0
  for _ in $(seq 18); do   # 18 polls x 5 s = 90 s
    N=$(gh run list --workflow "$CI_WORKFLOW" --commit "$HEAD_SHA" --event pull_request \
      --json databaseId -q 'length') || N=0
    [ "${N:-0}" -gt 0 ] && { FOUND=1; break; }
    sleep 5
  done
fi
```

`FOUND=0` after the loop is a timeout: report it and flip anyway.

## Flip to ready

Snapshot the head's run ids first, so the confirmation can tell a run the flip started from an
earlier draft one:

```bash
RUNS_BEFORE=$(gh run list --workflow "$CI_WORKFLOW" --commit "$HEAD_SHA" --event pull_request \
  --json databaseId -q 'map(.databaseId)') || RUNS_BEFORE='[]'
gh pr ready "$PR_NUMBER"
```

In a cloud session `gh pr ready` fails, because the flip is a GraphQL mutation. The proxy's REST
route:

```bash
gh api --method POST "repos/{owner}/{repo}/pulls/$PR_NUMBER/ccr/ready_for_review"
```

Or the GitHub MCP `update_pull_request` call with `draft: false`.

## Confirm a ready run

A new run id for the head after the flip is the `ready_for_review` run. 24 polls x 5 s = 120 s:

```bash
ready_run_seen() {
  for _ in $(seq 24); do
    N=$(gh run list --workflow "$CI_WORKFLOW" --commit "$HEAD_SHA" --event pull_request \
      --json databaseId -q "map(select(.databaseId as \$id | $RUNS_BEFORE | index(\$id) | not)) | length") || N=0
    [ "${N:-0}" -gt 0 ] && return 0
    sleep 5
  done
  return 1
}
```

When `ready_run_seen` returns 1, toggle once and wait again. A rerun replays the draft payload, so
it does not help:

```bash
RUNS_BEFORE=$(gh run list --workflow "$CI_WORKFLOW" --commit "$HEAD_SHA" --event pull_request \
  --json databaseId -q 'map(.databaseId)') || RUNS_BEFORE='[]'
gh pr ready "$PR_NUMBER" --undo && gh pr ready "$PR_NUMBER" && ready_run_seen
```

Exit 0 after the toggle means the run appeared; report the toggle either way. In a cloud session
the toggle goes through the same routes as the flip.
