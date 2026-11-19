---
bump: minor
---

### Added

- `limits.refire-budget-per-slot` (default 1). A work-unblock sweep re-fires issues whose lane run the start gate stopped on a low GITHUB_TOKEN budget, oldest run end first, only until the unfinished work-resolve-issue runs reach this value times the lane's `SLOTS`; those re-fires still count toward `limits.refire-queue-per-slot`'s room, and every other re-fire keeps two per slot. A budget-stopped run re-fired as the second run per slot often waited 20 to 47 minutes for a slot, past the 20-minute window after the reset, and the start gate stopped it again (owner decision, 2026-11-19).
