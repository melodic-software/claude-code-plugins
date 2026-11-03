---
bump: patch
---

### Fixed

- **The trigger-adapters template states the drain's admission labeler check correctly.** The drain reads who last applied the autonomous-eligible role label only, never a `work-class:` label (#12748).
