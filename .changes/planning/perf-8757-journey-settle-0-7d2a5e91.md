---
bump: none
---

### Changed

- surface-journey test: its browser session opens with playwright-cli's settle time at 0, so the twenty phase scripts, which wait for what they check themselves, no longer pay about 1 s each of post-script waiting.
