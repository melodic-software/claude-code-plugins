---
bump: minor
---

### Changed

- **Breaking:** the `verification` level now defaults to `light` when the default branch sets no `verification` key, holds an invalid value, or cannot be read: verifier dispatches are skipped and the skip line is written. Set `verification: standard` (or `strict`), or `verification_skills.<skill>`, in the team file on the default branch to raise it.
