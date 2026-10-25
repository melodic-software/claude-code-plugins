---
bump: minor
---

### Added

- The interview page shows drift between the ledger and the page while the interview runs ([#9719](https://github.com/melodic-software/claude-code-plugins/issues/9719)). `round.sh ledger-check [--ledger L]` compares the page with the ledger `import-ledger` seeded it from, as `export-ledger --diff` does, writes `meta.ledgerSync` (`{rev, rows}`) and adds an Activity Log line naming the first difference when the rows that disagree change; `wake.sh` runs it after each `apply` (`AFTER_APPLY=ledger-check` in `surface/session-bridge.conf`). The header reads `Ledger: N rows out of sync` or `Ledger in sync, rev N` and shows nothing for a data dir without the field. An accepted row with unticked commitments reads `Accepted, N to confirm` on the rail and the question's chip, and the meter's to-confirm count names each such row. `context/surface.md` and `surface/README.md` document the command, the field and the conf key.
