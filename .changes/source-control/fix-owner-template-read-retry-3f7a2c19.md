---
bump: patch
---

### Changed

- `create` retries a failed read of the owner's default pull request template once, then falls back to `briefing` and names the failed read in its report and the body, instead of stopping before the pull request opens.
