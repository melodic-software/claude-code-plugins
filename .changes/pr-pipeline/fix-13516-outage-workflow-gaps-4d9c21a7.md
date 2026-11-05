---
bump: patch
---

### Fixed

- `report-stop-status` posts no failing `pr-unblock/address-feedback` status for a `feedback-publish-failed` whose lane token was refused as workflow-modified or by a transient broker failure (`tokenRefusal`); it reads the run's jobs and annotations with `actions: read` and `checks: read`
- `API_BUDGET_HOLD: "1"` on work-unblock's label-unblocked step, the pr-unblock-dispatch dispatch step and pr-merge's candidate listing, whose scripts hold green on a refused call; every other lane workflow records why its steps stay unset
- pr-refine's `fix-docs-head` reads the PR head through `read-pr-head.bash`, so a transient fault is read once more
