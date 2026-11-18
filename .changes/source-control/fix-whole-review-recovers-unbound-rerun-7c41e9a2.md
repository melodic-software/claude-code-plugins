---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: a pull request held only by `evidence-unbound:<lane>` with the unbound reason `rerun-not-allowed` now gets the gate's whole-review request, so a new run at the same head can bind the review. No other unbound reason requests one, and the per-head, per-pull-request and per-sweep limits still apply. What the merge gate accepts does not change.
