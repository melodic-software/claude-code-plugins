---
bump: patch
---

### Changed

- `merge.skip-unchanged` is off (`max-minutes: 0`). Measured over 172 pr-merge runs, the skip filter spent about 2,230 calls to skip 12 of 637 candidates and saved about 521. enable-auto-merge's skip kept nothing in 56 runs. With it off, every candidate is gated and neither path reads its key.
