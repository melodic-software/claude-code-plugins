---
bump: minor
---

### Added

- The CI review lanes' prior-findings step reads `loop.findings-after-first-review` from the pipeline file the wrapper passes in `CAP_CONFIG` (the default branch's `docs/conventions/pr-pipeline.yaml`). With `all`, the `blocking only:` line reads `no` on every head, so the lanes report every finding after their first review. An absent key, an unknown value or an unread file keeps today's `blocking-only`.
