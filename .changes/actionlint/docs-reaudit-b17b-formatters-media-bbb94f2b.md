---
bump: patch
---

### Changed

- The `setup` skill's `apply install-git-hooks` step now lists every result the installer's `copy` prints (`installed`, `refreshed`, `unchanged`, `refused`, `blocked`, `unsafe-path`, `stage-failed`) and what each means.
- `setup`'s two `--config` gotchas point at the `plugin install` section of the CLI reference instead of quoting it.

No behavior change.
