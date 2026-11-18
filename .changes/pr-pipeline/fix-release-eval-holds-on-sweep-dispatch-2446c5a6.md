---
bump: patch
---

### Fixed

- pr-merge's eval-hold release also runs on a `workflow_dispatch` sweep (no `pr` input), so a valid hold no longer waits for a scheduled run the brake or token pacing skipped. A PR-scoped dispatch stays excluded, and the release's other conditions and limits are unchanged.
