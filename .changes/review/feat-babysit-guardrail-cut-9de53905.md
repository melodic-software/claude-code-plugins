---
bump: minor
---

### Changed

- `/review:security-review` marks each inline comment with one `severity:` line above the lane footer and its summary with one `critical-findings:` line. Only a CRITICAL finding holds the merge; every other finding flags it, a manifest `flag` line included.
