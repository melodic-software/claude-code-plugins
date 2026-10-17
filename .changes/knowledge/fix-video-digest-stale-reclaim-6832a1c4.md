---
bump: patch
---

### Fixed

- `video-digest` `queue-claim.js stale-check` now resets a stale claim's `QUEUE.md` row from `in_progress` to `pending` when it deletes the stub, and lists `in_progress` rows that have no stub as `orphaned`. The watch-queue spoke now says the CLI owns the reset.
- `queue-claim.js claim` now exits `1` for a row number that is not in `QUEUE.md` instead of recording a phantom claim, and accepts `--claimed-by <name>` to record the session holding the claim.
