# Stacked pull requests

A stack is a chain of pull requests in one repository: the bottom layer targets the trunk (usually
the default branch) and each layer above targets the branch of the layer below. Only a native stack,
one GitHub records as a stack, behaves as one. A PR that merely targets another PR's branch is not a
stack layer: merging it lands that PR alone, into that branch.

## When to stack

Stack only pull requests that genuinely depend on each other: the upper one cannot build, test or
be reviewed without the lower one's change. Independent changes go in separate PRs off the trunk.

A stack saves the trunk merge into the next PR, not CI time. Every layer runs its own checks and
review lanes, and each restack re-runs them on every layer above the change. The PR-pipeline lanes
that act on a PR (refine, unblock) skip any layer whose base is not the default branch. Keep stacks
short, and fix a lower layer before the upper layers collect review.

- **Pointer**: for what the queue, CI and the review lanes did with a two-layer stack, read the
  probe results in the pull request that closed
  [#7664](https://github.com/melodic-software/claude-code-plugins/issues/7664).
- **As of**: 2026-10-16
- **Recheck trigger**: the review lanes change how they scope a re-review, or the PR-pipeline
  lanes start accepting PRs into a non-default base.

## Create

- Build the stack with GitHub's `gh stack` extension (`github/gh-stack`). Read its commands from
  the CLI reference below rather than from memory.
- Put each dependency in the same layer or a lower one, never a higher one.
- Each layer is a pull request in its own right: open it with `create`, take it through `ready` and
  `monitor`, and hold its title and body to the same contract as any other PR.
- Inside a linked worktree (`/source-control:worktree`), use an extension release that tracks
  stacks per repository, and the Git floor the CLI reference names. Unattended lanes set
  `GH_STACK_NO_UPDATE_NOTIFIER=1` to keep its upgrade notice out of their output.
- After pushing to a lower layer, restack the layers above yourself (`gh stack rebase`, then
  `gh stack push`).

- **Pointer**: when you need a command, the worktree requirements or the environment switches,
  fetch [Stacked PRs CLI commands](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands#worktree-support)
  live; correlate with the
  [gh-stack v0.2.0 release notes](https://github.com/github/gh-stack/releases/tag/v0.2.0) for
  per-repository tracking.
- **As of**: 2026-10-16
- **Recheck trigger**: the extension's next minor release, or that page changes its worktree
  section.

## Merge

- Merging a layer lands it and every open layer below it, all or nothing. Run the Phase 4.1
  readiness re-verification ([merge.md](merge.md)) on **every** layer that will land, not only the
  one you merge, and get the user's approval for the whole set.
- Merge with the extension's merge command or the async merge API ([merge.md](merge.md) §4.2). The
  synchronous REST merge endpoint does not support stacks.
- The trunk's rules govern every layer, and GitHub evaluates them when the merge runs, not when it
  is requested. A stack merge cannot bypass them.
- After a partial merge, expect the layers above to re-run their checks and review lanes on their
  new head before they are ready again.
- Treat a stack as merging until every one of its PRs reads `MERGED`; on a trunk with a merge
  queue, read how the queue takes the stack from the pointer below, live.
- `/source-control:babysit-prs` holds stack layers for a human unless its `babysit_stacked_prs`
  option is on.

- **Pointer**: when you need how a stack merges, its rules and CI, or its merge methods, fetch
  [About stacked pull requests: Rules, CI, and merging](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs#rules-ci-and-merging)
  live; for the merge command and its queue handling,
  [Stacked PRs CLI commands: gh stack merge](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands#gh-stack-merge);
  for the synchronous endpoint's limit,
  [Merge a pull request](https://docs.github.com/rest/pulls/pulls?apiVersion=2026-03-10#merge-a-pull-request).
  Correlate with the
  [general availability changelog](https://github.blog/changelog/2026-10-06-stacked-pull-requests-generally-available/)
  and with the queue probe in the pull request that closed
  [#7664](https://github.com/melodic-software/claude-code-plugins/issues/7664).
- **As of**: 2026-10-16
- **Recheck trigger**: either docs page changes how a stack queues or merges, or a stack in a
  merge queue lands its layers in separate passes.
