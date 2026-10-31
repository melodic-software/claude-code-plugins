---
bump: patch
---

### Fixed

- `ledger-check` now checks the ledger that `sync-ledger` or `add-round --sync-ledger` last wrote, recorded as `meta.syncedLedger`, before the ledger the page was seeded from. Both commands also record the check in `meta.ledgerSync`, so the page header shows its ledger line on an interview that was never imported from a ledger ([#11586](https://github.com/melodic-software/claude-code-plugins/issues/11586)).
