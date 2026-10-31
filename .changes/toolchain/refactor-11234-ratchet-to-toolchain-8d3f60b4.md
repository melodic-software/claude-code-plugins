---
bump: minor
---

### Added

- `/toolchain:ratchet`, moved from the review plugin, where it was /review:ratchet: holds a lint violation, suppression, performance or telemetry count at a checked-in CI ceiling that fails on a rise and is lowered as the count falls. Its new `reference/zero-entries.md` states the zero-entry rule: a baseline or allowlist that reaches zero entries is deleted in the same change, with the code that reads it and that code's tests.
- `prerequisites.json` declares Python 3 as optional for `/toolchain:ratchet`, so `/toolchain:check-prerequisites` reports it.
