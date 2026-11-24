---
bump: patch
---

### Fixed

- The lane readers of the trusted-actor list fail closed when the standards list is unavailable, and never fall back to the synced `.github/standards/trusted-actors` copy, which goes stale once standards stops syncing it. `trustedListPath` reads the standards checkout (`STANDARDS_DIR`), else a path the workflow passes under it, else throws; `read-status`'s `loadTrustedActors` no longer reads the `BASE_PATH` copy; `resolve-config` without a standards checkout loads no trusted-actor list (the vocabulary still falls back); ci-status's `trusted_list` no longer reads the hold config's copy. `check-born-triaged`, `check-trusted-trigger` and `select-trusted-text` drop their `trusted-actors-path` input, whose default was the `.base` copy.
