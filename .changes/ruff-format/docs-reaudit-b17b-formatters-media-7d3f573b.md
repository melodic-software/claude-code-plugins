---
bump: patch
---

### Changed

- The `setup` skill's `apply install-git-hooks` step now lists every result the installer's `copy` prints (`installed`, `refreshed`, `unchanged`, `refused`, `blocked`, `unsafe-path`, `stage-failed`) and what each means.
- `setup` points at uv's `uv add` reference for the `--no-sync` record-only example instead of restating uv's sync behavior.

No behavior change.
