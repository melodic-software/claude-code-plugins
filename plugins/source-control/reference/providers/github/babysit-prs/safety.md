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
`merge-async` endpoint, then a `GET` on the request's UUID.

### A CLI merge the queue took

`gh pr merge` adds a PR to the queue on any base that has one, `--auto` or not, and exits `0`.

**Claim, basis, as of, recheck:** that `gh pr merge` adds a PR to a required merge queue, or
enables auto-merge until its checks pass, and exits `0` for a PR already queued,
[merging a pull request with a merge queue](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/merging-a-pull-request-with-a-merge-queue),
the [`gh pr merge` manual](https://cli.github.com/manual/gh_pr_merge), and
[`pkg/cmd/pr/merge/merge.go`](https://github.com/cli/cli/blob/trunk/pkg/cmd/pr/merge/merge.go);
the queue fields read back (`isInMergeQueue`, `isMergeQueueEnabled`, `mergeQueueEntry`,
`autoMergeRequest`), the
[`PullRequest` GraphQL object](https://docs.github.com/en/graphql/reference/objects#pullrequest);
why a PR leaves the queue, the first page's removal section; 2026-10-04. Recheck when a `gh`
release changes how `gh pr merge` treats a queue base, or the GraphQL schema changes a queue field.

## Rerun a rate-limited review

Rerun the whole workflow run with `gh run rerun <run-id>`, never `gh run rerun --failed`.
