# babysit-prs safety on GitHub

This file serves the babysit-prs [safety spoke](../../../../skills/babysit-prs/reference/safety.md):
it holds the GitHub commands and CLI facts for the operations that spoke names. The spoke owns
every rule, invariant and refusal around them. The [GitHub provider reference](../README.md)
indexes the other operations.

## True PR head and push destination

The spoke's Checkout And Push Invariants:

- The true PR head is `gh pr view <N> --json headRefOid`.
- The PR checkout is `gh pr checkout`, and a coincidental same-tip match on another local branch
  heals by running it. The remote it configures is never pushed to.
- Same-repo or fork comes from `gh pr view --json isCrossRepository`, and a fork head's owner from
  `gh pr view --json headRepositoryOwner`.
- The push is `push-branch.sh --dir <checkout> --pr <N>`. In a lane its destination is
  `lane-push.sh`'s own read, `gh pr view <N> -R <owner/repo> --json headRepository,headRefName`,
  from which it builds `https://github.com/<nameWithOwner>.git`; attended, it is the resolved push
  remote, whose push URLs must each be the PR's head repository on github.com (`gh pr view <N> --json
  headRepository,headRepositoryOwner`).

## CLI merge

The spoke's "CLI merge" is `gh pr merge`. It carries the head pin as `--match-head-commit`
(`gh pr merge --match-head-commit`), the CLI counterpart of the async merge API's `sha`.

The async merge API is called with `gh api` (`gh` has no subcommand for it): a `PUT` to the PR's
`merge-async` endpoint, then a `GET` on the request's UUID. It carries direct merges only.

### Enqueue

A merge-queue base is enqueued with `gh api graphql` and the `enqueuePullRequest` mutation:
`pullRequestId` is the PR's `node_id`, read over REST, and `expectedHeadOid` is the vetted head.
`jump` is never sent. The REST `merge-async` call with `merge_action=merge_queue` answers a GitHub
App installation token with "Enqueuer is not authorized to merge", so the gate does not use it.

- **Pointer:** [`enqueuePullRequest`](https://docs.github.com/en/graphql/reference/pulls#enqueuepullrequest).
- **As of:** 2026-10-14.
- **Recheck trigger:** that mutation or its input changes, or GitHub documents App enqueue through
  `merge-async`.

### A CLI merge the queue took

The spoke's queue read-back after a successful CLI merge reads these GraphQL fields:
`isInMergeQueue`, `isMergeQueueEnabled`, `mergeQueueEntry` and `autoMergeRequest`.

- **Pointer**: when you need how `gh pr merge` acts on a merge-queue base, fetch
  [Adding a pull request to a merge queue](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/merging-a-pull-request-with-a-merge-queue#adding-a-pull-request-to-a-merge-queue)
  and the [`gh pr merge` manual](https://cli.github.com/manual/gh_pr_merge) live; correlate with
  [`pkg/cmd/pr/merge/merge.go`](https://github.com/cli/cli/blob/trunk/pkg/cmd/pr/merge/merge.go).
- **Pointer**: when you need a queue field, fetch the
  [`PullRequest` GraphQL object](https://docs.github.com/en/graphql/reference/objects#pullrequest)
  live; when you need why a PR left the queue, fetch
  [Understanding why your pull request was removed from the merge queue](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/merging-a-pull-request-with-a-merge-queue#understanding-why-your-pull-request-was-removed-from-the-merge-queue)
  live.

## Rerun a lane run

- A review lane run (PR Review, PR Review Security) the App started binds its second attempt only
  when attempt 1 left no verdict: a kill switch or the upstream-status gate stopped it, it held or
  failed on a rate limit, it failed on a rejected credential or a failed install, or an outage lost
  it before the lane posted (`rerun_binds` in `babysit_review_evidence.py`). A third attempt never
  binds.
- Otherwise start a fresh App-triggered head with `gh pr update-branch <n>`. Never `gh run rerun`
  an App-started lane run (PR Review, PR Review Security, pr-verify) whose attempt 1 reviewed the
  head: attempt 2 runs on the owner login, and the gate refuses it as `evidence-unbound:<lane>`
  with the reason `rerun-not-allowed`.
- A rate-limited review reruns the whole workflow run (`gh run rerun <run-id>`), never
  `gh run rerun --failed`: a status job that reads another job's output would re-read the cached
  failed result.

## Resolve identity on a person-opened PR

The spoke's own-PR exception resolves a lane-answered thread under the PR author's login, and the
lanes App does not resolve threads on a PR a person opened.

- **Pointer**: when deciding which identity can resolve a thread on a person-opened PR, fetch
  [Resolving conversations](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/commenting-on-a-pull-request#resolving-conversations)
  live; the probe is [pr-unblock run 40737011221](https://github.com/melodic-software/claude-code-plugins/actions/runs/40737011221)
  (`publish-feedback / run`, a lanes App resolve on a person-opened PR that failed). **As of**:
  2026-10-28. **Recheck trigger**: a lanes App resolve on a person-opened PR succeeds, or that
  section changes who may resolve a conversation.
