# Plan: ledger sync

Container: #200. Branch: `feat/ledger-sync`.

## Phase 1. Sync worker (done)

- [x] Scaffold the sync worker.
- [x] Agree the retry policy.

## Phase 2. Conflict resolution (open)

Precondition: the webhook receiver is wired to the sync worker.

- [ ] Resolve concurrent edits to one ledger row by last-writer-wins with an audit entry.
- [ ] Add tests for two writers on one row.

## Phase 3. Backfill (later)

- [ ] Backfill the historical ledgers from the nightly exports.
