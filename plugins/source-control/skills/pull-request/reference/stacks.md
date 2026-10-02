# Stacked pull requests

A stack is a chain of pull requests in one repository: the bottom layer targets the trunk (usually
the default branch) and each layer above targets the branch of the layer below. Only a native stack,
one GitHub records as a stack, behaves as one. A PR that merely targets another PR's branch is not a
stack layer: merging it lands that PR alone, into that branch.

## Create

- Build the stack with GitHub's `gh stack` extension (`github/gh-stack`). Its quickstart and CLI
  reference, linked below, carry the commands; read them there rather than from memory, since the
  feature is in public preview.
- Put each dependency in the same layer or a lower one, never a higher one.
- Each layer is a pull request in its own right: open it as a draft, take it through `ready` and
  `monitor`, and hold its title and body to the same contract as any other PR.

## Merge

- Merging a layer lands it and every open layer below it, all or nothing. Run the Phase 4.1
  readiness re-verification ([merge.md](merge.md)) on **every** layer that will land, not only the
  one you merge, and get the user's approval for the whole set.
- Merge with the extension's merge command or the async merge API ([merge.md](merge.md) §4.2). The
  synchronous REST merge endpoint does not support stacks.
- The trunk's rules govern every layer, and GitHub evaluates them when the merge runs, not when it
  is requested. A stack merge cannot bypass them.
- Merging a lower layer leaves the layers above open; GitHub retargets them to the trunk and rebases
  them.
- On a trunk that requires a merge queue the stack is enqueued, and its layers can land in separate
  groups. Treat it as queued until each PR reads `MERGED`.
- `/source-control:babysit-prs` holds stack layers for a human unless its `babysit_stacked_prs`
  option is on.

**Claim, basis, as of, recheck:** stack shape, trunk rules, and merge behavior,
[about stacked pull requests](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs);
the extension, its merge-time rule evaluation, and its queue behavior,
[stacked pull requests CLI commands](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands)
and [quickstart](https://docs.github.com/en/pull-requests/get-started/stacked-prs-quickstart); the
synchronous endpoint's limit,
[merge a pull request](https://docs.github.com/rest/pulls/pulls?apiVersion=2026-03-10#merge-a-pull-request);
public preview,
[stacked pull requests changelog](https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview);
2026-10-02. Recheck when stacked pull requests leave public preview, or when either docs page
changes how a stack merges or queues.
