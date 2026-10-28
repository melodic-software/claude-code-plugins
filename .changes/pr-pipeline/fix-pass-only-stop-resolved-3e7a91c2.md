---
bump: patch
---

### Fixed

- A pass-only `address-feedback` round (sent with `verify-pass-head`) that finds no stale pr-verify fail-note thread now runs the full thread select and reports `stop-resolved`, so `report-stop-status` can clear a failing `pr-unblock/address-feedback` status an earlier attempt of the round left on the head, as on a rerun after the notes were resolved by hand. It still starts no model or reply job.
