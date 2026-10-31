---
bump: patch
---

### Fixed

- A `pr-verify` run the lanes kill switch stopped now gets its re-run on the first reconciler pass
  after the switch lifts. `maintenance-reconcile-lost-runs` placed every pull request's CI set
  before any lane run and took lane runs oldest first, so flake re-runs used the three places and
  the few left went to runs of pull requests that had already moved on. A green lanes App pull
  request sat on `verify:missing` until someone re-ran `ci-status` by hand. Lane runs now go after
  every set except a flake-only one, newest first. The deferral note no longer says
  `3 re-runs in flight` when this pass's own placements took the places.
