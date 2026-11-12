---
bump: patch
---

### Fixed

- prior-findings: reading `loop.findings-after-first-review` now runs in linear time on blank and whitespace-only lines, so a crafted pipeline file can no longer stall the read.
