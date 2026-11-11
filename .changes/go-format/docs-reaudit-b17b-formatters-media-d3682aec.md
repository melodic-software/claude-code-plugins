---
bump: patch
---

### Changed

- The `setup` skill's `apply install-git-hooks` step now lists every result the installer's `copy` prints (`installed`, `refreshed`, `unchanged`, `refused`, `blocked`, `unsafe-path`, `stage-failed`) and what each means.
- `setup`'s "does NOT do" list now names the read-only `goimports -h` probe and the installer commands `check` and `apply` run, instead of claiming no tool runs.

No behavior change.
