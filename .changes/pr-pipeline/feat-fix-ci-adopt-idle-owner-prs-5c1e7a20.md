---
bump: minor
---

### Added

- A top-level `adoption` section (`idle-hours`, default 24; `owner-ids`, default empty) names
  owner accounts whose pull requests the lanes adopt. pr-unblock-dispatch starts `fix-ci` for a
  non-draft owner PR whose `ci-status` failed once its last update and its head commit are both
  `idle-hours` old, with no `do-not-merge`, `needs-human` or tracker human-gated label and no
  body line starting `Hold:` (babysit's reading: any case, after any whitespace, a bare CR ends
  a line). This repository adopts kyle-sexton's PRs after 24 hours (owner decision Q22).

### Changed

- While `adoption.owner-ids` lists anyone, the tracker's human-gated label also holds lanes App
  PRs from `fix-ci`. A base `.work-item-tracker.json` that is not JSON holds only the adopted
  owner PRs, and fails the dispatcher run; lanes App PRs still get `fix-ci`.
