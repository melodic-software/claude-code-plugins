---
bump: patch
---

### Changed

- **Test suite only; nothing shipped changes.** The audit-skill-visibility churn tests clear git's read-only object files when removing their fixture repo, so the temp dir is no longer left behind on Windows.
