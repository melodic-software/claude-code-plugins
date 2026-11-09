# Branch update criteria

Why each row of [`branch-update-method.sh`](../scripts/branch-update-method.sh) picks its method.
The script owns every condition and the row order; read it for those. The order of the rows is
judgment throughout.

## Rows

### `no-update-needed`

We skip an update unless something calls for it, because every update costs a CI run and leaves a
new head to check. [The kernel guide on rebasing](https://docs.kernel.org/maintainer/rebasing-and-merging.html#rebasing)
and [GitHub on keeping a pull request in sync](https://docs.github.com/en/pull-requests/how-tos/create-pull-requests/keeping-your-pull-request-in-sync-with-the-base-branch#about-keeping-your-pull-request-in-sync)
disagree on whether a newer base alone justifies an update.

- **Pointer**: when judging whether a head must be up to date under its status checks, fetch [required status checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-status-checks-before-merging) live.
- **Pointer**: when the base uses a merge queue, fetch [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue#about-merge-queues) live.
- **As of**: 2026-11-08
- **Recheck trigger**: either GitHub section changes what it asks of the head, or the two
  disagreeing pages come to agree.

### `safety-unknown`

`judgment`. Skipping one update is cheap to repeat; guessing wrong about who owns a head or whether
it sits in a stack is not.

- **Recheck trigger**: a run reports this row for a head whose owner or stack membership was
  readable.

### `managed-head`

`judgment`. We leave a branch to the dependency manager that owns it and ask the manager for the
update.

- **Recheck trigger**: a supported dependency manager stops regenerating branches it opened.

### `native-stack`

We update a native stack member by rebase, in line with GitHub's rules for stack history and stack
rebases. An ad hoc chain of pull requests is not a native stack and falls to the rows below.

- **Pointer**: when checking what merging a stack requires of its history, fetch [linear history](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests#linear-history) live.
- **Pointer**: when checking what a stack rebase keeps or produces, fetch [rebasing](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests#rebasing) live.
- **As of**: 2026-11-08
- **Recheck trigger**: either section changes what it requires of a stack or what a stack rebase
  retains.

### `native-stack-blocked`

`judgment`. When the rebase a stack member needs is off the table, we use neither method: the update
is reported and left to a person.

- **Pointer**: when checking what merging a stack requires of its history, fetch [linear history](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests#linear-history) live.
- **As of**: 2026-11-08
- **Recheck trigger**: GitHub adds a way to update a stack member without a rewrite.

### `shared-history`

We do not rewrite history that another person's work depends on. Treating an unreadable answer as a
yes is `judgment`: the merge it costs is recoverable and an overwritten commit may not be.

- **Pointer**: when weighing a rewrite of history others created, fetch [the kernel guide on rebasing](https://docs.kernel.org/maintainer/rebasing-and-merging.html#rebasing) live.
- **Pointer**: when weighing a rewrite of pushed commits, fetch [Pro Git: the perils of rebasing](https://git-scm.com/book/en/v2/Git-Branching-Rebasing#_rebase_peril) live.
- **As of**: 2026-11-08
- **Recheck trigger**: either page changes its rule on rewriting shared history.

### `no-rewrite`

We use the method the actor can carry out, since an update that cannot be pushed is an update not
done. Applying this to every blocked actor is `judgment`.

- **Pointer**: when checking whether auto mode lets a session force push, fetch [what the classifier blocks by default](https://code.claude.com/docs/en/permission-modes#what-the-classifier-blocks-by-default) live.
- **Pointer**: when a person approves a force push in the session, fetch [approvals you state in conversation](https://code.claude.com/docs/en/permission-modes#approvals-you-state-in-conversation) live.
- **As of**: 2026-11-08
- **Recheck trigger**: the classifier's default block list changes its entry for force push.

### `base-merged`

We do not rebase a head that took the base by merge, because of how a rebase handles merge commits;
treating an unreadable answer as a yes is `judgment`.

- **Pointer**: when judging what a rebase does to merge commits, fetch [git-rebase `--rebase-merges`](https://git-scm.com/docs/git-rebase#Documentation/git-rebase.txt---rebase-mergesrebase-cousinsno-rebase-cousins) live.
- **As of**: 2026-11-08
- **Recheck trigger**: a git release changes that option's text.

### `human-reviewed`

The choice is `judgment`: a merge keeps the commits the reviewer read and adds the new ones on top.
Choosing a merge does not settle whether approvals survive, so a run reads the repository's
stale-review setting and warns before acting.

- **Pointer**: when judging whether an approval survives an update, fetch [pull request reviews](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-pull-request-reviews-before-merging) live.
- **As of**: 2026-11-08
- **Recheck trigger**: that section changes when an approval goes stale.

### `squash-landing`

On a squash landing we choose the method with no rewrite, a `judgment` drawn from what a squash
merge keeps on the base.

- **Pointer**: when checking what a squash merge keeps, fetch [squash and merge](https://docs.github.com/en/pull-requests/reference/pull-request-merges#squash-and-merge-your-commits) live.
- **As of**: 2026-11-08
- **Recheck trigger**: that section changes what a squash merge keeps.

### `keeps-commits`

These commits reach the base as they are, so we keep merges of the base out of them when nobody else
depends on them. Preferring rebase here is `judgment`.
[GitHub on merging often](https://docs.github.com/en/pull-requests/reference/branches#merging-often)
and [the kernel guide on merging from upstream](https://docs.kernel.org/maintainer/rebasing-and-merging.html#merging-from-sibling-or-upstream-trees)
disagree on merging the base into a topic branch.
[Pro Git: rebase when you rebase](https://git-scm.com/book/en/v2/Git-Branching-Rebasing#_rebase_rebase)
and Fossil's page on rebase ([section 2.0](https://fossil-scm.org/home/doc/trunk/www/rebaseharm.md#20-rebase-provides-no-new-capabilities),
[section 5.0](https://fossil-scm.org/home/doc/trunk/www/rebaseharm.md#50-rebase-misrepresents-the-project-history))
disagree on whether to rebase at all.

- **As of**: 2026-11-08
- **Recheck trigger**: either pair of pages comes to agree, or Pro Git changes its condition for
  rewriting pushed commits.

### `default-merge`

`judgment`. With no row calling for a rewrite, we take the option with no rewrite to recover from.

- **Recheck trigger**: a run reports this row for a case a named row should have decided.

## Carrying out the method

`push-branch.sh`'s `sync_stale_base` step still merges under a forced rebase: it carries out a merge
already chosen and never reads this decision.
[The update sequence](../skills/pull-request/reference/ready-for-review.md#decide-and-carry-out-the-update)
says when a push passes `--no-sync-stale-base`, so that step cannot update a branch the decision
left alone. `none` needs no
flag, because `branch-update-signals.sh` reports no base change needed only when the overlap check
finds none, and that step merges only on an overlap. A head already holding the base tip has nothing
to merge.

A rebase pushes with the pinned lease only, and CI retests the rebased head.

- **Pointer**: when choosing a lease form, fetch [git-push `--force-with-lease`](https://git-scm.com/docs/git-push#Documentation/git-push.txt---force-with-lease) live.
- **Pointer**: when deciding how far to retest a rebased series, fetch [the kernel guide on rebasing](https://docs.kernel.org/maintainer/rebasing-and-merging.html#rebasing) live.
- **As of**: 2026-11-08
- **Recheck trigger**: git-push changes its lease option text, or the kernel guide changes its
  retesting rule.
