---
bump: patch
---

### Fixed

- The lane room keeps an unverified-stale post-merge answer when the only verifying run that
  reached a conclusion since is one its check already read finished (`judgedRuns` in the
  post-merge report), instead of running the post-merge check again.
