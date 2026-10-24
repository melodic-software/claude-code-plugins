---
bump: patch
---

### Fixed

- babysit-prs never merges the base into a Dependabot head (a `dependabot/` branch Dependabot opened). A commit by anyone else stops Dependabot's own rebases, drops the PR's changelog-fragment exemption and fails the Dependabot merge tier's commit check. The unattended enqueue, for a stale Dependabot head that is not an eligible Dependabot update, and `refresh_pr_branch.py --apply` now post one comment per base tip instead of calling `update-branch`, and hold the PR as `dependabot-rebase-requested`: `@dependabot rebase` when every commit is Dependabot's, `@dependabot recreate` when the other commits are only base merges GitHub made (Dependabot refuses to rebase a branch someone else committed to). At most one request is posted an hour, unless the head conflicts with its base. A head with any other commit gets no comment and holds as `dependabot-branch-edited`, because a recreate would discard that commit.
- The pull-request skill's behind-branch step and its base refresh before ready point at the Dependabot exception, and that exception now names `@dependabot recreate` for a branch whose only foreign commits are base merges.
