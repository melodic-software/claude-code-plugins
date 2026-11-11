---
bump: patch
---

### Changed

- The `setup` skill's `apply install-git-hooks` step now lists every result the installer's `copy` prints (`installed`, `refreshed`, `unchanged`, `refused`, `blocked`, `unsafe-path`, `stage-failed`) and what each means.
- `setup` no longer mentions a pre-computed row, since the skill has none.

No behavior change.
