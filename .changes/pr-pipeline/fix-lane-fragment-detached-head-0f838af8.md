---
bump: patch
---

### Fixed

- The issue lane can create changelog fragments on its detached checkout:
  `collect-base-activity` sets `CHANGELOG_FRAGMENT_BRANCH` to
  `work-resolve-issue/issue-<n>-<run id>-<attempt>` in the
  `new-changelog-fragment` wrapper, and `scripts/new-changelog-fragment.sh`
  names a detached HEAD's fragment after it instead of refusing.
