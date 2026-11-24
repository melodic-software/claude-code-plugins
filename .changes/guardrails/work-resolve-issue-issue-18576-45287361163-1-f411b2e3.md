---
bump: minor
---

### Added

- `retirements.yaml` records `guardrails-r005` to `guardrails-r024` cover what the `reference-verify` git-hook entry, removed in 4.0.0, installed: the `pre-push.d/guardrails.reference-verify` marker, the `guardrails/reference-verify.sh` copy and the eight assets beside it (`run-guards.sh`, `abort-boundary.sh`, `hook-utils.sh`, `cli-flag-verify.sh`, `skill-reference-verify.sh`, `stale-path-verify.sh`, `verify-cli-flag.sh`, `cli-flag-cache.sh`). `r005` to `r014` cover `.git/hooks/`, found from a linked worktree too; `r015` to `r024` cover a shared `.githooks/`. `/guardrails:setup check` reports each copy, and `apply` removes each one you confirm. A file at one of these paths whose content does not match the record, such as your own, is left alone.

### Changed

- The `reference-verify` removal steps in `/guardrails:setup` and the README now list all eight assets and cover only what the records do not: a lefthook job, a husky line, and a copy under `.githooks/local/` or another `core.hooksPath`.
