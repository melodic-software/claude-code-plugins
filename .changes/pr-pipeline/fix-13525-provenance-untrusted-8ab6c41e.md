---
bump: minor
---

### Changed

- The CI lanes hold an issue labeled `provenance: untrusted` exactly as they hold one labeled
  `work-class: untrusted-provenance`, and still read the old name: admission, intake's verdict
  apply, the issue lane's blocker gate and merge hold, work-unblock's re-fire and the triage sweep.
  Both names live once, in `merge-holds.mjs` (`UNTRUSTED_LABELS`); writers still apply the old
  name.
