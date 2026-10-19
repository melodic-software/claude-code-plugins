---
bump: patch
---

### Fixed

- `pr-run-activity-read.yml` takes the write file's `trusted-base` input and passes it to
  `check-trusted-base`, and pr-unblock's `fix-ci` job passes `trusted-base: default-tip`, as every
  other pr-unblock job does. A lane PR opened before `fix-ci` joined the config kept a base SHA
  whose config had no `fix-ci` slot, so every dispatched `fix-ci` run on it failed at "Resolve the
  config". `version` stays 2.
