---
bump: patch
---

### Fixed

- The babysit merge gate reads a pull request's force pushes 100 at a time up to 1,000, so a pull request rebased more than 100 times no longer fails its risk gate with `force pushes: unread or past one page` on every run and never arms. A listing past 1,000, a missing cursor or a count the pages do not reach still raises.
