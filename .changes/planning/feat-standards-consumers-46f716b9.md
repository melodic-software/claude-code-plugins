---
bump: minor
---

### Added

- `/planning:design` resolves the consumer's standards through the standards contract's Resolution ladder in Phase 1, so design threads start from the conventions the work will be reviewed against.
- `/planning:interview`, `/planning:design` and `/planning:plan` follow the contract's new "Adopted shipped concepts" rule (standards contract 1.3.1): a loaded standards file that cites shipped concept ids has its counterweights and conflicts looked up with `/engineering-concepts:lookup` (if enabled) and kept beside each entry.
- A loader test per stage runs the plugin's `scripts/org-standards.sh subscriptions` against a fixture subscription and checks the stage points at the ladder.
