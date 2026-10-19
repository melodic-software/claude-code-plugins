---
bump: minor
---

### Added

- `merge.check-inputs`: git pathspecs the pull request checks read. When main changed one since a
  pull request's merge base, the pr-merge lane updates the pull request from main instead of
  enqueuing it. The default lists the shared-copy registry (`scripts/shared-copies.txt`) and the
  docs-only allowlist (`scripts/docs-only-paths.txt`).
