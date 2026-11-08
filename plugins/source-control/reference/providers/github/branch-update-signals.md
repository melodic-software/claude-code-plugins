# GitHub: branch update signals

Which GitHub reads `scripts/branch-update-signals.sh` makes, and the decisions behind them. The
signals and their rules are in the script and the
[criteria doc](../../branch-update-criteria.md); a read that fails is `unknown`, `blocked` for
`rewrite`.

## The pull request

`conflict`, `native_stack`, `managed_head` and the head and base names come from one read of the
REST pull object; `up_to_date_required` reads it and the rules below, and `behind` comes from
compare. `conflict` and `behind` use GitHub's own computation rather than local git, so they hold
from any checkout.

`native_stack` is the object's `stack` field: an object means a member, a missing or null one
means none, the same read babysit's stack gate makes.

`up_to_date_required` is `yes` when the object's `mergeable_state` is `behind`, and otherwise when
a `required_status_checks` rule on the base is strict with at least one check. When no rule says
strict it reads classic protection's required status checks: `strict` true is `yes`, false is `no`,
a 404 is `no`, and any other failure is `unknown`. A strict rule answers with no classic read. A
token without access to protection therefore reads `unknown`, never `no`.

- **Pointer**: when a field's meaning is in question, fetch
  [Get a pull request](https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request) live; for
  classic protection, fetch
  [Get status checks protection](https://docs.github.com/en/rest/branches/branch-protection#get-status-checks-protection)
  live.
- **As of**: 2026-11-08
- **Recheck trigger**: either section renames or removes `mergeable`, `mergeable_state`, `stack` or
  `strict`.

## Commits and reviews

`other_authors` and `human_review` read the REST commits and reviews lists, not `gh pr view`. A
commit counts by its `author` account, so a co-author trailer is not another author. When the list
holds fewer commits than the pull object counts, `other_authors` is `unknown`. A review counts when
its state is `APPROVED`, `CHANGES_REQUESTED` or `COMMENTED`.

- **Pointer**: when the commit list's limit or fields are in question, fetch
  [List commits on a pull request](https://docs.github.com/en/rest/pulls/pulls#list-commits-on-a-pull-request)
  live; for reviews, fetch
  [List reviews for a pull request](https://docs.github.com/en/rest/pulls/reviews#list-reviews-for-a-pull-request).
- **As of**: 2026-11-08
- **Recheck trigger**: the commit list's maximum changes, or a review's `commit_id` or user type
  changes shape.

## Behind

`behind` reads `behind_by` from compare, from the base's name to the head SHA. The base is given by
name for the reason [freshness](babysit-prs/freshness.md) records.

- **Pointer**: when compare's fields or its `basehead` forms are in question, fetch
  [Compare two commits](https://docs.github.com/en/rest/commits/commits#compare-two-commits) live.
- **As of**: 2026-11-08
- **Recheck trigger**: that section changes `behind_by` or the `basehead` forms.

## Rules

Branch rules are read for the base (`up_to_date_required`, the merge queue's method for `landing`)
and for the head (`non_fast_forward` for `rewrite`). The branch name is percent-encoded as one path
segment.

- **Pointer**: when a rule's type or parameters are in question, fetch
  [Get rules for a branch](https://docs.github.com/en/rest/repos/rules#get-rules-for-a-branch) live.
- **As of**: 2026-11-08
- **Recheck trigger**: that section renames `non_fast_forward`, `merge_queue`, `merge_method` or
  `strict_required_status_checks_policy`.

## Landing

Without a merge queue, `landing` is `squash` when the repository allows squash, otherwise
`keeps-commits` when it allows a merge or a rebase. Repository settings are read through
`gh repo view --json`, with the default branch, in one call. `babysit_merge_method` is not read: it
is deprecated. Configured extra dependency-manager and bot logins are not read either; `managed_head`
uses the built-in list and `human_review` the account type and `[bot]` suffix.

- **Pointer**: when the JSON fields are in question, fetch
  [gh repo view: JSON fields](https://cli.github.com/manual/gh_repo_view#json-fields) live.
- **As of**: 2026-11-08
- **Recheck trigger**: `gh repo view` renames a merge-method field.

## Branch-only mode

With no pull request yet, `native_stack` reads the local `gh stack` record in git's common
directory by its JSON field path: a branch the record names is a member, an absent record means
none, and a record that does not parse is `unknown`. No docs page covers the record's file name or
fields, so the pointer is the source.

- **Pointer**: when the record's location or fields are in question, fetch
  [gh-stack's stack file](https://github.com/github/gh-stack/blob/main/internal/stack/stack.go)
  live.
- **As of**: 2026-11-08
- **Recheck trigger**: a docs page starts covering the record's file name or fields, or gh-stack
  renames the file or its `stacks`, `branches` or `branch` fields.
