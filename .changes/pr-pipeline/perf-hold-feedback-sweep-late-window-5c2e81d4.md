---
bump: minor
---

### Changed

- pr-dispatch-feedback's scheduled sweep sends no round while GITHUB_TOKEN's core pool is under `sweep-hold` (0.2) of its limit and resets within `sweep-hold-minutes` (15), both new github-token fields in `rate-limits.json`. Those rounds would stop at the stop floor before finishing; the first tick after the reset decides the same heads again. A tick that has read no rate-limit header never holds.
