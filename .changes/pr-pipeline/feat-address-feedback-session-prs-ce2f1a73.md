---
bump: minor
---

### Added

- `adoption.feedback-idle-minutes` (30 in this repository): `address-feedback` works a session PR, one a trusted person opened, once its head was pushed that many minutes ago, or at once while a `lanes-may-fix` label whose newest `labeled` event a trusted person made is on it; never past `do-not-merge` or a `Hold:` body line (owner rule, 2026-10-24). The half-hourly sweep takes such a PR whose head no round has worked, at most one dispatch per tick. A session push while the lane works supersedes the lane's patch instead of being overwritten. Absent, no session PR is worked (`.github/scripts/pr-unblock/feedback-dispatch.mjs`).
