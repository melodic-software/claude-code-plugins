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
`HEAD_BEFORE`, `HEAD_SHA`, `RUNS_BEFORE`, `ready_run_seen` and `runs_skipped`. When 2.5.2 is skipped,
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

The run lists here and below name no workflow: they count every `pull_request` run for the head
SHA, so they work in any repository without knowing its CI file name. A run listed for the head
SHA means the push's event reached the workflows; the wait does not look at any run's result. The
push starts one run per workflow, and they may register a few seconds apart, so the wait ends only
when the count is above zero and unchanged across two polls, which keeps a late sibling out of the
flip's snapshot. Skip the wait when the head is unchanged, but still run the `HEAD_SHA`
assignment, which the flip block reads.

```bash
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid -q '.headRefOid') || exit 1
if [ "$HEAD_SHA" != "$HEAD_BEFORE" ]; then
  FOUND=0 PREV=0
  for _ in $(seq 18); do   # 18 polls x 5 s = 90 s
    N=$(gh run list --commit "$HEAD_SHA" --event pull_request -L 100 \
      --json databaseId -q 'length') || N=0
    [ "${N:-0}" -gt 0 ] && [ "$N" = "$PREV" ] && { FOUND=1; break; }
    PREV=${N:-0}
    sleep 5
  done
fi
```

`FOUND=0` after the loop is a timeout: report it and flip anyway.

`--commit` and `--event` filter the list server side, and `-L 100` lifts the default page so a
repository with many workflows is counted in full. Pointer:
[gh run list](https://cli.github.com/manual/gh_run_list) for the flags and the default limit. As
of: 2026-10-18. Recheck trigger: a gh release that changes `run list` filtering or its default
limit.

## Flip to ready

Snapshot the head's run ids first, so the confirmation can tell a run the flip started from an
earlier draft one:

```bash
RUNS_BEFORE=$(gh run list --commit "$HEAD_SHA" --event pull_request -L 100 \
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

A new run id for the head after the flip shows a run started, not that it carries the ready
payload: a draft-payload run that registers late is also a new id, and it cancels the ready run
through the per-PR concurrency group. Define `ready_run_seen` first, always, since the toggle below
calls it (24 polls x 5 s = 120 s):

```bash
ready_run_seen() {
  for _ in $(seq 24); do
    N=$(gh run list --commit "$HEAD_SHA" --event pull_request -L 100 \
      --json databaseId -q "map(select(.databaseId as \$id | $RUNS_BEFORE | index(\$id) | not)) | length") || N=0
    [ "${N:-0}" -gt 0 ] && return 0
    sleep 5
  done
  return 1
}
```

When the wait above timed out (`FOUND=0`), the push's run had not registered when `RUNS_BEFORE` was
taken and a new id proves nothing: do not call `ready_run_seen` here, go straight to the toggle,
which starts a run after the draft one has registered. Otherwise call it right after the flip:

```bash
ready_run_seen
```

When it returns 1, toggle once and wait again. A rerun replays the draft payload, so it does not
help:

```bash
RUNS_BEFORE=$(gh run list --commit "$HEAD_SHA" --event pull_request -L 100 \
  --json databaseId -q 'map(.databaseId)') || RUNS_BEFORE='[]'
gh pr ready "$PR_NUMBER" --undo && gh pr ready "$PR_NUMBER" && ready_run_seen
```

Exit 0 after the toggle means a new run appeared; report it as "a new run appeared", never as a
confirmed ready run, and report the toggle either way. In a cloud session
the toggle goes through the same routes as the flip.

## Check the new runs did not skip

A new run id is not a ready run: a draft-payload run that registers after `RUNS_BEFORE` was taken
is a new id too, and its lanes read the PR as a draft and skip. Once `ready_run_seen` returns 0,
read the conclusions of the runs not in `RUNS_BEFORE` for up to 180 seconds (36 polls x 5 s),
ending early on the first `skipped` one. A skipped run completes within seconds, while a ready run
takes minutes, so the window catches the skip without waiting for the ready run to finish:

```bash
runs_skipped() {
  SKIPPED=unknown
  for _ in $(seq 36); do
    S=$(gh run list --commit "$HEAD_SHA" --event pull_request -L 100 --json databaseId,conclusion \
      -q "map(select(.databaseId as \$id | $RUNS_BEFORE | index(\$id) | not)) | any(.conclusion == \"skipped\")") || S=""
    [ "$S" = true ] && { SKIPPED=true; return 0; }
    [ "$S" = false ] && SKIPPED=false
    sleep 5
  done
  return 1
}
runs_skipped
```

`SKIPPED=true` means the flip lost the race. `false` is clean. `unknown` means every read failed:
report it as a failed check, never as clean. A run that skips for its own reason (a label, actor or
path filter) reads the same, so it costs one re-fire and a second skip report, never a loop.

On `true`, re-fire once, unless the toggle above already ran: that toggle was the one re-fire, and a
skip after it is reported, never re-fired:

```bash
RUNS_BEFORE=$(gh run list --commit "$HEAD_SHA" --event pull_request -L 100 \
  --json databaseId -q 'map(.databaseId)') || RUNS_BEFORE='[]'
gh pr ready "$PR_NUMBER" --undo && gh pr ready "$PR_NUMBER" && ready_run_seen && runs_skipped
```

After the toggle above, run `runs_skipped` once on its runs as well. A second `true` is reported
and the PR stays ready. If the undo succeeds and the second `ready` fails, flip again by the route
that works and report it; the PR must not stay a draft. In a cloud session the re-fire goes through
the same routes as the flip.
