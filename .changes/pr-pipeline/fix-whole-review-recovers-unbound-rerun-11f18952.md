---
bump: patch
---

### Fixed

- pr-merge's whole-review request also covers a pull request held only by `evidence-unbound:<lane>` whose unbound reason is `rerun-not-allowed`: a new run at the same head binds where the re-run did not. No other unbound reason requests one, the once-per-head, twice-per-pull-request and once-per-run limits are unchanged, and what the merge gate accepts does not change.
