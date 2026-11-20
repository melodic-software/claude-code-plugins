---
bump: patch
---

### Fixed

- pr-merge's whole-review request also covers a pull request held only by `evidence-unbound:<lane>` whose unbound reason is `base-retargeted`. Review evidence now binds only on lane runs created after the newest base change, so a new run at the same head binds where a review against the old base did not. The once-per-head, twice-per-pull-request and once-per-run limits are unchanged.
