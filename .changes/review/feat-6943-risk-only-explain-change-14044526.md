---
bump: minor
---

### Added

- **`/review:explain-change --risk-only`** rates a pull request's risk areas without the digest, page, or policy check, runs the same fresh-context check on them, and returns a JSON result with `demote: true` when any area, or the checker's level for it, is HIGH or CRITICAL. The result may only send an unattended merge to a human; it never makes a pull request merge-eligible. No merge gate reads it yet.
