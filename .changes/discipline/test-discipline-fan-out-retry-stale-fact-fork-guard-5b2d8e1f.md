---
bump: patch
---

### Added

- `do-your-research` has eval cases for a fan-out worker that errors twice (one retry, then reported unverifiable) and for a planted stale fact the ledger must flag as corrected.

### Changed

- The sweep-all fork-guard eval prompts for `do-your-research` and `recheck-against-upstream` no longer say "audit-only" or "self-audit only", and the cases now assert that the skills' own never-inside-a-fork guard keeps the fork inline when its Agent tool could spawn.
