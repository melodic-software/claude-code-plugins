---
bump: minor
---

### Added

- A top-level `adoption` section (`idle-hours`, default 24; `owner-ids`, default empty) names
  owner accounts whose pull requests the lanes adopt. pr-unblock-dispatch starts `fix-ci` for a
  non-draft owner PR whose `ci-status` failed once its last update and its head commit are both
  `idle-hours` old, with no `do-not-merge` or `needs-human` label and no body line starting
  `Hold:`. This repository adopts kyle-sexton's PRs after 24 hours (owner decision Q22). Lanes App
  PRs are unchanged.
